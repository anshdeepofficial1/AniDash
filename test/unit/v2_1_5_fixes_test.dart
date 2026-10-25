import 'package:flutter_test/flutter_test.dart';
import 'package:ani_dash/core/utils/language_utils.dart';
import 'package:better_player_plus/better_player_plus.dart';

void main() {
  group('LanguageUtils Tests', () {
    test('resolves German and other foreign languages correctly', () {
      expect(LanguageUtils.getShortName('de'), 'German');
      expect(LanguageUtils.getShortName('fr'), 'French');
      expect(LanguageUtils.getShortName('es'), 'Spanish');
      expect(LanguageUtils.getShortName('ja'), 'Japanese');
      expect(LanguageUtils.getShortName('en'), 'English');
      expect(LanguageUtils.getShortName(null, fallback: 'Original'), 'Original');
    });

    test('generates dynamic SUB and DUB labels based on source language', () {
      expect(LanguageUtils.getSubLabel('de'), 'German (SUB)');
      expect(LanguageUtils.getDubLabel('de'), 'German (DUB)');
      expect(LanguageUtils.getSubLabel('ja'), 'Japanese (SUB)');
      expect(LanguageUtils.getDubLabel('ja'), 'English (DUB)');
      expect(LanguageUtils.getSubLabel(null), 'Japanese (SUB)');
      expect(LanguageUtils.getDubLabel(null), 'English (DUB)');
    });

    test('formats audio language properly', () {
      expect(LanguageUtils.formatAudioLanguage('sub', 'de'), 'German SUB');
      expect(LanguageUtils.formatAudioLanguage('dub', 'de'), 'German DUB');
      expect(LanguageUtils.formatAudioLanguage('sub', 'ja'), 'Japanese SUB');
      expect(LanguageUtils.formatAudioLanguage('dub', 'ja'), 'English DUB');
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
