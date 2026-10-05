enum NamedEpisodeGroupType { arc, saga, season, custom }

class NamedEpisodeGroup {
  const NamedEpisodeGroup({
    required this.id,
    required this.animeId,
    required this.title,
    required this.startEpisode,
    required this.endEpisode,
    required this.type,
    required this.sortOrder,
    required this.source,
    required this.updatedAt,
    this.episodeIds = const <int>[],
  });

  final String id;
  final String animeId;
  final String title;
  final int startEpisode;
  final int endEpisode;
  final List<int> episodeIds;
  final NamedEpisodeGroupType type;
  final int sortOrder;
  final String source;
  final DateTime updatedAt;

  bool contains(int episode) =>
      episodeIds.isNotEmpty
          ? episodeIds.contains(episode)
          : episode >= startEpisode && episode <= endEpisode;

  String get rangeLabel => '$startEpisode–$endEpisode';
}
