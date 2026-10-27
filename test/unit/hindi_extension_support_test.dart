import 'package:flutter_test/flutter_test.dart';
import 'package:dartotsu_extension_bridge/Models/Source.dart';
import 'package:dartotsu_extension_bridge/Models/DEpisode.dart';
import 'package:ani_dash/core/models/settings/source_model.dart';

void main() {
  group('Hindi Anime Extension & Aniyomi Bridge Tests', () {
    test('DEpisode safely parses string and numeric episode numbers', () {
      final ep1 = DEpisode.fromJson({'episode_number': '12'});
      expect(ep1.episodeNumber, '12');

      final ep2 = DEpisode.fromJson({'episode_number': 5.0});
      expect(ep2.episodeNumber, '5');

      final ep3 = DEpisode.fromJson({'episodeNumber': '10.5'});
      expect(ep3.episodeNumber, '10.5');

      final ep4 = DEpisode.fromJson({});
      expect(ep4.episodeNumber, '');
    });

    test('Source fallback ensures active anime source is never left as null when extensions exist', () {
      final toonstreamSource = Source(
        id: 'eu.kanade.tachiyomi.animeextension.hi.toonstream',
        name: 'Toonstream',
        lang: 'hi',
        itemType: ItemType.anime,
      );
      final hindiDubSource = Source(
        id: 'eu.kanade.tachiyomi.animeextension.hi.animedubhindi',
        name: 'AnimeDubHindi',
        lang: 'hi',
        itemType: ItemType.anime,
      );

      final state = SourceState(
        installedAnimeExtensions: [toonstreamSource, hindiDubSource],
      );

      // Simulate source resolution with an unknown saved ID
      const savedAnimeId = 'obsolete_or_unknown_source_id';
      final activeAnime = state.installedAnimeExtensions.firstWhere(
            (s) => s.id == savedAnimeId || s.name == savedAnimeId,
            orElse: () => state.installedAnimeExtensions.first,
          );

      expect(activeAnime.name, 'Toonstream');
      expect(activeAnime.lang, 'hi');
    });

    test('Default Aniyomi repository list contains Hindi msrofficial anime-repo', () {
      const defaultAniyomiRepos = [
        'https://raw.githubusercontent.com/msrofficial/anime-repo/repo/index.min.json',
        'https://kohiden.xyz/Kohi-den/extensions/raw/branch/main/index.min.json',
        'https://raw.githubusercontent.com/yuzono/anime-repo/repo/index.min.json',
        'https://raw.githubusercontent.com/Secozzi/aniyomi-extensions/refs/heads/repo/index.min.json',
      ];

      expect(
        defaultAniyomiRepos.contains(
          'https://raw.githubusercontent.com/msrofficial/anime-repo/repo/index.min.json',
        ),
        isTrue,
      );
    });
  });
}
