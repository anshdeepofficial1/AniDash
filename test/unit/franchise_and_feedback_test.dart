import 'package:flutter_test/flutter_test.dart';
import 'package:ani_dash/core/models/universal/universal_media.dart';
import 'package:ani_dash/core/services/franchise_service.dart';

void main() {
  group('Universal Franchise & Arc Recognition Tests', () {
    UniversalMedia makeMedia({
      required String id,
      required String title,
      String format = 'TV',
      int? year,
      int? month,
      int? day,
      int? seasonYear,
    }) {
      return UniversalMedia(
        id: id,
        title: UniversalTitle(english: title, romaji: title),
        coverImage: const UniversalCoverImage(large: 'https://example.com/cover.jpg'),
        format: format,
        seasonYear: seasonYear ?? year,
        startDate: UniversalFuzzyDate(year: year, month: month, day: day),
      );
    }

    test('Demon Slayer canon arcs are cleanly labeled', () {
      final s1 = makeMedia(id: '1', title: 'Demon Slayer: Kimetsu no Yaiba');
      final mugenTv = makeMedia(
        id: '2',
        title: 'Demon Slayer: Kimetsu no Yaiba Mugen Train Arc',
      );
      final entertainment = makeMedia(
        id: '3',
        title: 'Demon Slayer: Kimetsu no Yaiba Entertainment District Arc',
      );
      final swordsmith = makeMedia(
        id: '4',
        title: 'Demon Slayer: Kimetsu no Yaiba Swordsmith Village Arc',
      );
      final hashira = makeMedia(
        id: '5',
        title: 'Demon Slayer: Kimetsu no Yaiba Hashira Training Arc',
      );
      final infinity = makeMedia(
        id: '6',
        title: 'Demon Slayer: Kimetsu no Yaiba the Movie: Infinity Castle',
        format: 'MOVIE',
      );

      expect(FranchiseService.deriveCleanSeasonChipLabel(s1, 1), 'Season 1');
      expect(FranchiseService.deriveCleanSeasonChipLabel(mugenTv, 2), 'Mugen Train Arc');
      expect(FranchiseService.deriveCleanSeasonChipLabel(entertainment, 3), 'Entertainment District Arc');
      expect(FranchiseService.deriveCleanSeasonChipLabel(swordsmith, 4), 'Swordsmith Village Arc');
      expect(FranchiseService.deriveCleanSeasonChipLabel(hashira, 5), 'Hashira Training Arc');
      expect(FranchiseService.deriveCleanSeasonChipLabel(infinity, 6), 'Infinity Castle Arc');
    });

    test('Roman numeral seasons are recognized across titles', () {
      final mob2 = makeMedia(id: '10', title: 'Mob Psycho 100 II');
      final mob3 = makeMedia(id: '11', title: 'Mob Psycho 100 III');
      final overlord4 = makeMedia(id: '12', title: 'Overlord IV');

      expect(FranchiseService.deriveCleanSeasonChipLabel(mob2, 2), 'Season 2');
      expect(FranchiseService.deriveCleanSeasonChipLabel(mob3, 3), 'Season 3');
      expect(FranchiseService.deriveCleanSeasonChipLabel(overlord4, 4), 'Season 4');
    });

    test('Word season titles and stages are recognized', () {
      final wordSeason = makeMedia(id: '20', title: 'Kimi ni Todoke 3rd Season');
      final r2 = makeMedia(id: '21', title: 'Code Geass: Lelouch of the Rebellion R2');
      final stage = makeMedia(id: '22', title: 'Initial D Second Stage');

      expect(FranchiseService.deriveCleanSeasonChipLabel(wordSeason, 3), 'Season 3');
      expect(FranchiseService.deriveCleanSeasonChipLabel(r2, 2), 'Season 2');
      expect(FranchiseService.deriveCleanSeasonChipLabel(stage, 2), 'Season 2');
    });

    test('Popular franchises arcs (Bleach TYBW, JJK, Dr. Stone, AoT) are formatted', () {
      final tybw = makeMedia(id: '30', title: 'Bleach: Thousand-Year Blood War - The Separation');
      final jjkShibuya = makeMedia(id: '31', title: 'Jujutsu Kaisen: Shibuya Incident Arc');
      final drStone = makeMedia(id: '32', title: 'Dr. STONE Stone Wars');
      final aotFinal = makeMedia(id: '33', title: 'Attack on Titan The Final Season Part 2');

      expect(FranchiseService.deriveCleanSeasonChipLabel(tybw, 16), 'TYBW: The Separation');
      expect(FranchiseService.deriveCleanSeasonChipLabel(jjkShibuya, 2), 'Shibuya Incident Arc');
      expect(FranchiseService.deriveCleanSeasonChipLabel(drStone, 2), 'Season 2: Stone Wars');
      expect(FranchiseService.deriveCleanSeasonChipLabel(aotFinal, 4), 'Season 4 Part 2');
    });

    test('Chronological release order sort accurately orders franchise items', () {
      final s1 = makeMedia(id: '1', title: 'Demon Slayer S1', year: 2019, month: 4, day: 6);
      final s2 = makeMedia(id: '2', title: 'Demon Slayer Mugen Train Arc', year: 2021, month: 10, day: 10);
      final s3 = makeMedia(id: '3', title: 'Demon Slayer Entertainment District Arc', year: 2021, month: 12, day: 5);
      final s4 = makeMedia(id: '4', title: 'Demon Slayer Swordsmith Village Arc', year: 2023, month: 4, day: 9);
      final s5 = makeMedia(id: '5', title: 'Demon Slayer Hashira Training Arc', year: 2024, month: 5, day: 12);

      final shuffled = [s4, s2, s5, s1, s3];
      shuffled.sort((a, b) {
        final aKey = (a.startDate?.year ?? 9999) * 10000 + (a.startDate?.month ?? 1) * 100 + (a.startDate?.day ?? 1);
        final bKey = (b.startDate?.year ?? 9999) * 10000 + (b.startDate?.month ?? 1) * 100 + (b.startDate?.day ?? 1);
        return aKey.compareTo(bKey);
      });

      expect(shuffled.map((e) => e.id).toList(), ['1', '2', '3', '4', '5']);
    });
  });
}
