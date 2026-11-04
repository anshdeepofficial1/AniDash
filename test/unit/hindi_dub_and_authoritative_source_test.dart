import 'package:flutter_test/flutter_test.dart';
import 'package:ani_dash/core/utils/language_utils.dart';
import 'package:ani_dash/shared/providers/anime_match_service.dart';

void main() {
  group('Hindi Dub Availability & Authoritative Source Tests', () {
    test('LanguageUtils correctly identifies Hindi extensions and sources', () {
      expect(LanguageUtils.isHindiSourceNameOrLang(name: 'Toonstream', lang: 'hi'), isTrue);
      expect(LanguageUtils.isHindiSourceNameOrLang(name: 'AnimeDubHindi', lang: 'hin'), isTrue);
      expect(LanguageUtils.isHindiSourceNameOrLang(name: 'Moviebox Hindi', lang: 'all'), isTrue);
      expect(LanguageUtils.isHindiSourceNameOrLang(name: 'JustAnime', lang: 'en'), isFalse);
      expect(LanguageUtils.isHindiSourceNameOrLang(name: 'HiAnime', lang: 'en'), isFalse);
      expect(LanguageUtils.isHindiSourceNameOrLang(name: 'AniKoto', lang: 'en'), isFalse);
    });

    test('AnimeMatchService cache returns null for unverified anime and handles cache keys', () {
      expect(AnimeMatchService.isHindiAvailableCached('test-unseen-id-9999'), isNull);
    });

    test('LanguageUtils correctly detects Hindi episode titles', () {
      expect(LanguageUtils.isHindiEpisode('Episode 1 [Hindi Dub]'), isTrue);
      expect(LanguageUtils.isHindiEpisode('Episode 1 (Hin Dub)'), isTrue);
      expect(LanguageUtils.isHindiEpisode('Episode 1 [Hin]'), isTrue);
      expect(LanguageUtils.isHindiEpisode('Episode 1 (English Dub)'), isFalse);
      expect(LanguageUtils.isHindiEpisode('Episode 1'), isFalse);
    });
  });
}
