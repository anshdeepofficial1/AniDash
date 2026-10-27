import 'package:flutter_test/flutter_test.dart';
import 'package:ani_dash/helpers/matcher.dart';

class MockAnime {
  final String id;
  final String name;

  MockAnime({required this.id, required this.name});
}

void main() {
  group('Hindi Title Matcher & Normalization Tests', () {
    test('Matches titles with (Hindi Dubbed) suffix with high score', () {
      final results = [
        MockAnime(id: '1', name: 'Naruto Shippuden (Hindi Dubbed)'),
        MockAnime(id: '2', name: 'Bleach'),
        MockAnime(id: '3', name: 'One Piece'),
      ];

      final matches = getBestMatches<MockAnime>(
        results: results,
        title: 'Naruto Shippuden',
        nameSelector: (r) => r.name,
        idSelector: (r) => r.id,
      );

      expect(matches.isNotEmpty, isTrue);
      expect(matches.first.result.id, equals('1'));
      expect(matches.first.similarity, greaterThanOrEqualTo(0.75));
    });

    test('Matches titles with "in Hindi" or "Hindi Dub" without penalty', () {
      final results = [
        MockAnime(id: '10', name: 'Demon Slayer in Hindi (Dual Audio)'),
        MockAnime(id: '20', name: 'Demon Slayer Season 2'),
      ];

      final matches = getBestMatches<MockAnime>(
        results: results,
        title: 'Demon Slayer',
        nameSelector: (r) => r.name,
        idSelector: (r) => r.id,
      );

      expect(matches.isNotEmpty, isTrue);
      expect(matches.first.result.id, equals('10'));
      expect(matches.first.similarity, greaterThanOrEqualTo(0.70));
    });

    test('Season 2 in Hindi matches Season 2 query and avoids Season 1', () {
      final results = [
        MockAnime(id: '1', name: 'Jujutsu Kaisen Season 1 (Hindi Dub)'),
        MockAnime(id: '2', name: 'Jujutsu Kaisen Season 2 (Hindi Dub)'),
      ];

      final matches = getBestMatches<MockAnime>(
        results: results,
        title: 'Jujutsu Kaisen Season 2',
        nameSelector: (r) => r.name,
        idSelector: (r) => r.id,
      );

      expect(matches.isNotEmpty, isTrue);
      expect(matches.first.result.id, equals('2'));
    });
  });
}
