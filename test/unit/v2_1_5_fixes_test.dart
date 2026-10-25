import 'package:flutter_test/flutter_test.dart';
import 'package:ani_dash/core/utils/language_utils.dart';
import 'package:ani_dash/core/models/settings/player_model.dart';
import 'package:better_player_plus/better_player_plus.dart';

void main() {
  group('LanguageUtils Tests', () {
    test('resolves German and other foreign languages correctly', () {
      expect(LanguageUtils.getShortName('de'), 'German');
      expect(LanguageUtils.getShortName('fr'), 'French');
      expect(LanguageUtils.getShortName('es'), 'Spanish');
      expect(LanguageUtils.getShortName('ja'), 'Japanese');
      expect(LanguageUtils.getShortName('en'), 'English');
      expect(LanguageUtils.getShortName('hi'), 'Hindi');
      expect(LanguageUtils.getShortName('hin'), 'Hindi');
      expect(LanguageUtils.getShortName('hindi'), 'Hindi');
      expect(LanguageUtils.getShortName(null, fallback: 'Original'), 'Original');
    });

    test('generates dynamic SUB and DUB labels based on source language', () {
      expect(LanguageUtils.getSubLabel('de'), 'German (SUB)');
      expect(LanguageUtils.getDubLabel('de'), 'German (DUB)');
      expect(LanguageUtils.getSubLabel('ja'), 'Japanese (SUB)');
      expect(LanguageUtils.getDubLabel('ja'), 'English (DUB)');
      expect(LanguageUtils.getSubLabel('hi'), 'Hindi (SUB)');
      expect(LanguageUtils.getDubLabel('hi'), 'Hindi (DUB)');
      expect(LanguageUtils.getSubLabel(null), 'Japanese (SUB)');
      expect(LanguageUtils.getDubLabel(null), 'English (DUB)');
    });

    test('formats audio language properly', () {
      expect(LanguageUtils.formatAudioLanguage('sub', 'de'), 'German SUB');
      expect(LanguageUtils.formatAudioLanguage('dub', 'de'), 'German DUB');
      expect(LanguageUtils.formatAudioLanguage('sub', 'ja'), 'Japanese SUB');
      expect(LanguageUtils.formatAudioLanguage('dub', 'ja'), 'English DUB');
      expect(LanguageUtils.formatAudioLanguage('dub', 'hi'), 'Hindi DUB');
      expect(LanguageUtils.formatAudioLanguage('sub', 'hi'), 'Hindi SUB');
    });

    test('detects language dynamically from genres or title', () {
      // 1. From genres
      expect(
        LanguageUtils.detectLanguage(genres: ['Action', 'Hindi', 'Shounen']),
        'Hindi',
      );
      expect(
        LanguageUtils.detectLanguage(genres: ['Hindi Dub', 'Adventure']),
        'Hindi',
      );
      expect(
        LanguageUtils.detectLanguage(genres: ['German', 'Fantasy']),
        'German',
      );

      // 2. From title
      expect(
        LanguageUtils.detectLanguage(title: 'Solo Leveling [Hindi Dub]'),
        'Hindi',
      );
      expect(
        LanguageUtils.detectLanguage(title: 'Attack on Titan (German)'),
        'German',
      );

      // 3. Explicit sourceLang overrides fallback
      expect(
        LanguageUtils.detectLanguage(
          sourceLang: 'fr',
          genres: ['Hindi'],
          title: 'Naruto',
        ),
        'French',
      );
    });
  });

  group('PlayerModel autoEnableSubtitles Tests', () {
    test('defaults autoEnableSubtitles to true', () {
      final model = PlayerModel();
      expect(model.autoEnableSubtitles, isTrue);
    });

    test('serializes and deserializes autoEnableSubtitles accurately', () {
      final model = PlayerModel(autoEnableSubtitles: true);
      expect(model.autoEnableSubtitles, isTrue);

      final jsonString = model.toJson();
      final restored = PlayerModel.fromJson(jsonString);
      expect(restored.autoEnableSubtitles, isTrue);

      final toggled = restored.copyWith(autoEnableSubtitles: false);
      expect(toggled.autoEnableSubtitles, isFalse);
    });
  });

  group('BetterPlayerSubtitle ASS Parsing Tests', () {
    test('parses standard ASS Dialogue line accurately', () {
      const assLine = 'Dialogue: 0,0:01:23.45,0:01:28.90,Default,,0,0,0,,{\\an8}Hello world!\\NThis is a test.';
      final sub = BetterPlayerSubtitle.fromAss(assLine);
      expect(sub.start, const Duration(minutes: 1, seconds: 23, milliseconds: 450));
      expect(sub.end, const Duration(minutes: 1, seconds: 28, milliseconds: 900));
      expect(sub.texts, ['Hello world!', 'This is a test.']);
    });

    test('ignores non-Dialogue lines in ASS', () {
      expect(BetterPlayerSubtitle.fromAss('[Events]').start, isNull);
      expect(BetterPlayerSubtitle.fromAss('Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text').start, isNull);
      expect(BetterPlayerSubtitle.fromAss('Comment: 0,0:00:00.00,0:00:05.00,Default,,0,0,0,,Note').start, isNull);
    });
  });
}
