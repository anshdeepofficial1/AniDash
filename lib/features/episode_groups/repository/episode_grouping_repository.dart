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
    _group('east-blue', 'East Blue', 1, 61, 0),
    _group('alabasta', 'Alabasta', 62, 143, 1),
    _group('skypiea', 'Skypiea', 144, 206, 2),
    _group('davy-back-fight', 'Davy Back Fight', 207, 228, 3),
    _group('water-seven', 'Water Seven', 229, 263, 4),
    _group('enies-lobby', 'Enies Lobby', 264, 336, 5),
    _group('thriller-bark', 'Thriller Bark', 337, 381, 6),
    _group('summit-war', 'Summit War', 382, 516, 7),
    _group('fish-man-island', 'Fish-Man Island', 517, 574, 8),
    _group('dressrosa', 'Dressrosa', 575, 746, 9),
    _group('four-emperors', 'Four Emperors', 747, 1085, 10),
    _group('final-saga', 'Final Saga', 1086, 9999, 11),
  ];

  static NamedEpisodeGroup _group(
    String id,
    String title,
    int start,
    int end,
    int order,
  ) => NamedEpisodeGroup(
    id: 'one-piece-$id',
    animeId: '21',
    title: title,
    startEpisode: start,
    endEpisode: end,
    type: NamedEpisodeGroupType.saga,
    sortOrder: order,
    source: 'AniDash verified mapping v1',
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

    final isOnePiece =
        animeId == '21' || malId == '21' || normalizedTitle == 'onepiece';
    return isOnePiece
        ? List<NamedEpisodeGroup>.unmodifiable(_onePiece)
        : const [];
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
