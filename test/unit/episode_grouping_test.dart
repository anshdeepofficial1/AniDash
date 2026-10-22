import 'package:flutter_test/flutter_test.dart';
import 'package:ani_dash/features/episode_groups/repository/episode_grouping_repository.dart';

void main() {
  test(
    'One Piece verified groups map episodes without gaps in supplied range',
    () async {
      final groups = await const VerifiedEpisodeGroupingRepository()
          .getNamedGroups(animeId: '21', title: 'One Piece');
      expect(groups, isNotEmpty);
      expect(groups.first.title, 'East Blue');
      expect(groups.first.contains(1), isTrue);
      expect(groups.first.contains(61), isTrue);
      expect(groups[2].title, 'Skypiea');
      expect(groups[2].contains(183), isTrue);
      final thrillerBark = groups.firstWhere((g) => g.title == 'Thriller Bark');
      expect(thrillerBark.contains(337), isTrue);
      final eniesLobby = groups.firstWhere((g) => g.title == 'Enies Lobby');
      expect(eniesLobby.contains(280), isTrue);
    },
  );

  test(
    'Bleach verified groups map episode 280 to Fall of the Arrancar',
    () async {
      final groups = await const VerifiedEpisodeGroupingRepository()
          .getNamedGroups(animeId: '269', title: 'Bleach');
      expect(groups, isNotEmpty);
      final arrancarFall = groups.firstWhere((g) => g.title == 'Fall of the Arrancar');
      expect(arrancarFall.contains(280), isTrue);
    },
  );

  test(
    'Hunter x Hunter maps episode 100 to Chimera Ant',
    () async {
      final groups = await const VerifiedEpisodeGroupingRepository()
          .getNamedGroups(animeId: '11061', title: 'Hunter x Hunter (2011)');
      expect(groups, isNotEmpty);
      final chimera = groups.firstWhere((g) => g.title == 'Chimera Ant');
      expect(chimera.contains(100), isTrue);
    },
  );

  test('unknown anime gracefully has no named groups', () async {
    final groups = await const VerifiedEpisodeGroupingRepository()
        .getNamedGroups(animeId: 'unknown', title: 'Unknown show');
    expect(groups, isEmpty);
  });
}
