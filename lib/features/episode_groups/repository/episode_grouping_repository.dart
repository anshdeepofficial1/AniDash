import 'dart:convert';
import 'package:ani_dash/features/episode_groups/model/named_episode_group.dart';
import 'package:ani_dash/main.dart';

abstract interface class EpisodeGroupingRepository {
  Future<List<NamedEpisodeGroup>> getNamedGroups({
    required String animeId,
    String? malId,
    String? title,
  });
}

class VerifiedEpisodeGroupingRepository implements EpisodeGroupingRepository {
  const VerifiedEpisodeGroupingRepository({this.remoteLoader});
  final Future<List<Map<String, Object?>>> Function(String animeId)?
  remoteLoader;

  static final DateTime _dataVersion = DateTime.utc(2026, 10, 3);

  // These are deliberately bundled, reviewed saga boundaries. The generic
  // repository contract allows a versioned remote source to be added later.
  static final List<NamedEpisodeGroup> _onePiece = <NamedEpisodeGroup>[
    _group('21', 'east-blue', 'East Blue', 1, 61, 0),
    _group('21', 'alabasta', 'Alabasta', 62, 135, 1),
    _group('21', 'skypiea', 'Sky Island', 136, 206, 2),
    _group('21', 'davy-back-fight', 'Davy Back Fight', 207, 228, 3),
    _group('21', 'water-seven', 'Water Seven', 229, 263, 4),
    _group('21', 'enies-lobby', 'Enies Lobby', 264, 336, 5),
    _group('21', 'thriller-bark', 'Thriller Bark', 337, 381, 6),
    _group('21', 'summit-war', 'Summit War', 382, 516, 7),
    _group('21', 'fish-man-island', 'Fish-Man Island', 517, 574, 8),
    _group('21', 'dressrosa', 'Dressrosa', 575, 746, 9),
    _group('21', 'four-emperors', 'Four Emperors', 747, 1085, 10),
    _group('21', 'final-saga', 'Final Saga', 1086, 9999, 11),
  ];

  static final List<NamedEpisodeGroup> _naruto = <NamedEpisodeGroup>[
    _group('20', 'land-of-waves', 'Land of Waves', 1, 19, 0),
    _group('20', 'chunin-exams', 'Chunin Exams', 20, 67, 1),
    _group('20', 'konoha-crush', 'Konoha Crush', 68, 80, 2),
    _group('20', 'search-for-tsunade', 'Search for Tsunade', 81, 106, 3),
    _group('20', 'sasuke-recovery', 'Sasuke Recovery', 107, 135, 4),
    _group('20', 'anime-original', 'Anime Original Missions', 136, 220, 5),
  ];

  static final List<NamedEpisodeGroup> _narutoShippuden = <NamedEpisodeGroup>[
    _group('1735', 'kazekage-rescue', 'Kazekage Rescue', 1, 32, 0),
    _group('1735', 'tenchi-bridge', 'Tenchi Bridge', 33, 53, 1),
    _group('1735', 'akatsuki-suppression', 'Akatsuki Suppression', 54, 88, 2),
    _group('1735', 'three-tails', 'Three-Tails', 89, 112, 3),
    _group('1735', 'itachi-pursuit', 'Itachi Pursuit', 113, 143, 4),
    _group('1735', 'six-tails', 'Six-Tails', 144, 151, 5),
    _group('1735', 'pain-assault', "Pain's Assault", 152, 175, 6),
    _group('1735', 'past', 'Past Arc', 176, 196, 7),
    _group('1735', 'five-kage-summit', 'Five Kage Summit', 197, 221, 8),
    _group('1735', 'war-countdown', 'Fourth War: Countdown', 222, 256, 9),
    _group(
      '1735',
      'war-confrontation',
      'Fourth War: Confrontation',
      257,
      321,
      10,
    ),
    _group('1735', 'war-climax', 'Fourth War: Climax', 322, 375, 11),
    _group('1735', 'ten-tails', 'Ten-Tails Jinchuriki', 376, 393, 12),
    _group('1735', 'new-chunin-exams', 'New Chunin Exams', 394, 413, 13),
    _group('1735', 'final-battle', 'Final Battle', 414, 479, 14),
    _group('1735', 'epilogue', 'Epilogue', 480, 500, 15),
  ];

  static final List<NamedEpisodeGroup> _bleach = <NamedEpisodeGroup>[
    _group('269', 'substitute', 'Substitute Shinigami', 1, 20, 0),
    _group('269', 'soul-society', 'Soul Society', 21, 63, 1),
    _group('269', 'bount', 'Bount', 64, 109, 2),
    _group('269', 'arrancar-begins', 'Arrancar Begins', 110, 167, 3),
    _group('269', 'amagi', 'New Captain Amagai', 168, 189, 4),
    _group('269', 'arrancar-battle', 'Arrancar vs Shinigami', 190, 229, 5),
    _group('269', 'zanpakuto', 'Zanpakuto Rebellion', 230, 265, 6),
    _group('269', 'arrancar-fall', 'Fall of the Arrancar', 266, 316, 7),
    _group('269', 'invading-army', 'Gotei 13 Invading Army', 317, 342, 8),
    _group('269', 'lost-agent', 'The Lost Agent', 343, 366, 9),
  ];

  static final List<NamedEpisodeGroup> _blackClover = <NamedEpisodeGroup>[
    _group('34572', 'entrance', 'Magic Knights Entrance', 1, 13, 0),
    _group('34572', 'dungeon', 'Dungeon Exploration', 14, 19, 1),
    _group('34572', 'royal-capital', 'Royal Capital Assault', 20, 27, 2),
    _group('34572', 'midnight-sun', 'Eye of the Midnight Sun', 28, 39, 3),
    _group('34572', 'seabed-temple', 'Seabed Temple', 40, 51, 4),
    _group('34572', 'witches-forest', "Witches' Forest", 52, 65, 5),
    _group('34572', 'royal-knights', 'Royal Knights', 66, 95, 6),
    _group('34572', 'elf-reincarnation', 'Elf Reincarnation', 96, 120, 7),
    _group('34572', 'heart-kingdom', 'Heart Kingdom', 121, 157, 8),
    _group('34572', 'spade-kingdom', 'Spade Kingdom', 158, 170, 9),
  ];

  static NamedEpisodeGroup _group(
    String animeId,
    String id,
    String title,
    int start,
    int end,
    int order,
  ) => NamedEpisodeGroup(
    id: '$animeId-$id',
    animeId: animeId,
    title: title,
    startEpisode: start,
    endEpisode: end,
    type: NamedEpisodeGroupType.saga,
    sortOrder: order,
    source: 'AniDash verified mapping v2',
    updatedAt: _dataVersion,
  );

  @override
  Future<List<NamedEpisodeGroup>> getNamedGroups({
    required String animeId,
    String? malId,
    String? title,
  }) async {
    final normalizedTitle = (title ?? '').toLowerCase().replaceAll(
      RegExp(r'[^a-z0-9]'),
      '',
    );
    final cacheKey = 'named_episode_groups_v1_$animeId';
    if (remoteLoader != null) {
      try {
        final remote =
            (await remoteLoader!(animeId))
                .map((item) => _fromRemote(item, animeId))
                .whereType<NamedEpisodeGroup>()
                .toList()
              ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
        if (remote.isNotEmpty) {
          await sharedPrefs.setString(
            cacheKey,
            jsonEncode(remote.map(_toJson).toList()),
          );
          return List.unmodifiable(remote);
        }
      } catch (_) {
        // A remote grouping outage must never block episode access.
      }
    }
    try {
      final raw = sharedPrefs.getString(cacheKey);
      if (raw != null) {
        final cached =
            (jsonDecode(raw) as List)
                .whereType<Map>()
                .map(
                  (item) =>
                      _fromRemote(Map<String, Object?>.from(item), animeId),
                )
                .whereType<NamedEpisodeGroup>()
                .toList();
        if (cached.isNotEmpty) return List.unmodifiable(cached);
      }
    } catch (_) {}

    final identity = malId ?? animeId;
    final groups = switch (identity) {
      '21' => _onePiece,
      '20' => _naruto,
      '1735' => _narutoShippuden,
      '269' => _bleach,
      '34572' => _blackClover,
      _ => switch (normalizedTitle) {
        'onepiece' => _onePiece,
        'naruto' => _naruto,
        'narutoshippuden' || 'narutoshippuuden' => _narutoShippuden,
        'bleach' => _bleach,
        'blackclover' => _blackClover,
        _ => const <NamedEpisodeGroup>[],
      },
    };
    return List<NamedEpisodeGroup>.unmodifiable(groups);
  }

  static NamedEpisodeGroup? _fromRemote(
    Map<String, Object?> value,
    String animeId,
  ) {
    final start = int.tryParse(value['startEpisode']?.toString() ?? '');
    final end = int.tryParse(value['endEpisode']?.toString() ?? '');
    final title = value['title']?.toString().trim() ?? '';
    final source = value['source']?.toString().trim() ?? '';
    if (start == null ||
        end == null ||
        start < 1 ||
        end < start ||
        title.isEmpty ||
        source.isEmpty) {
      return null;
    }
    return NamedEpisodeGroup(
      id: value['id']?.toString() ?? '$animeId-$start-$end',
      animeId: animeId,
      title: title,
      startEpisode: start,
      endEpisode: end,
      type: NamedEpisodeGroupType.values.firstWhere(
        (type) => type.name == value['type'],
        orElse: () => NamedEpisodeGroupType.custom,
      ),
      sortOrder: int.tryParse(value['sortOrder']?.toString() ?? '') ?? start,
      source: source,
      updatedAt:
          DateTime.tryParse(value['updatedAt']?.toString() ?? '') ??
          DateTime.now().toUtc(),
    );
  }

  static Map<String, Object?> _toJson(NamedEpisodeGroup group) => {
    'id': group.id,
    'title': group.title,
    'startEpisode': group.startEpisode,
    'endEpisode': group.endEpisode,
    'type': group.type.name,
    'sortOrder': group.sortOrder,
    'source': group.source,
    'updatedAt': group.updatedAt.toIso8601String(),
  };
}
