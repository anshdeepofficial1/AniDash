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
    },
  );

  test('unknown anime gracefully has no named groups', () async {
    final groups = await const VerifiedEpisodeGroupingRepository()
        .getNamedGroups(animeId: 'unknown', title: 'Unknown show');
    expect(groups, isEmpty);
  });
}
