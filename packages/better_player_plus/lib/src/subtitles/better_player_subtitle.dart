import 'package:better_player_plus/src/core/better_player_utils.dart';

class BetterPlayerSubtitle {
  factory BetterPlayerSubtitle(String value, bool isWebVTT) {
    try {
      final lines = value
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .toList();

      if (lines.isEmpty) {
        return BetterPlayerSubtitle._();
      }
      if (lines.any((l) => l.startsWith("NOTE") || l.startsWith("LANGUAGE"))) {
        return BetterPlayerSubtitle._();
      }

      int? index = -1;
      List<String> timeSplit = [];
      int firstLineOfText = 0;

      if (lines[0].contains(timerSeparator)) {
        timeSplit = lines[0].split(timerSeparator);
        firstLineOfText = 1;
      } else if (lines.length > 1 && lines[1].contains(timerSeparator)) {
        index = int.tryParse(lines[0]);
        timeSplit = lines[1].split(timerSeparator);
        firstLineOfText = 2;
      } else {
        return BetterPlayerSubtitle._();
      }

      if (timeSplit.length < 2) {
        return BetterPlayerSubtitle._();
      }

      final start = _stringToDuration(timeSplit[0]);
      final end = _stringToDuration(timeSplit[1]);
      final rawTexts = lines.sublist(firstLineOfText);
      final texts = rawTexts
          .map((t) => t.replaceAll(RegExp(r'<[^>]*>'), '').trim())
          .where((t) => t.isNotEmpty)
          .toList();

      return BetterPlayerSubtitle._(
        index: index,
        start: start,
        end: end,
        texts: texts.isNotEmpty ? texts : rawTexts,
      );
    } catch (e) {
      BetterPlayerUtils.log('Failed to parse subtitle component: $value ($e)');
    }
    return BetterPlayerSubtitle._();
  }

  factory BetterPlayerSubtitle.fromAss(String line) {
    try {
      final trimmed = line.trim();
      if (!trimmed.toLowerCase().startsWith('dialogue:')) {
        return BetterPlayerSubtitle._();
      }
      final raw = trimmed.substring(9).trim(); // Remove "Dialogue:"
      // ASS format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
      // Split into at most 10 tokens so the text token can safely contain commas
      final tokens = <String>[];
      var current = StringBuffer();
      for (int i = 0; i < raw.length; i++) {
        if (raw[i] == ',' && tokens.length < 9) {
          tokens.add(current.toString().trim());
          current.clear();
        } else {
          current.write(raw[i]);
        }
      }
      tokens.add(current.toString().trim());

      if (tokens.length < 10) {
        return BetterPlayerSubtitle._();
      }

      final start = _stringToDuration(tokens[1]);
      final end = _stringToDuration(tokens[2]);
      var rawText = tokens[9];

      // Replace ASS linebreaks (\N or \n) with real newlines
      rawText = rawText.replaceAll(RegExp(r'\\[Nn]'), '\n');
      // Strip ASS override tags like {\an8}, {\b1}, {\pos(x,y)}, etc.
      rawText = rawText.replaceAll(RegExp(r'\{[^}]*\}'), '');
      // Strip HTML tags like <i>, </b>, etc.
      rawText = rawText.replaceAll(RegExp(r'<[^>]*>'), '');
      // Clean drawing commands if present
      rawText = rawText.replaceAll(RegExp(r'\\h'), ' ').trim();

      final texts = rawText
          .split('\n')
          .map((t) => t.trim())
          .where((t) => t.isNotEmpty)
          .toList();

      if (start == Duration.zero && end == Duration.zero) {
        return BetterPlayerSubtitle._();
      }

      return BetterPlayerSubtitle._(
        index: null,
        start: start,
        end: end,
        texts: texts.isNotEmpty ? texts : [rawText],
      );
    } catch (e) {
      BetterPlayerUtils.log('Failed to parse ASS subtitle line: $line ($e)');
    }
    return BetterPlayerSubtitle._();
  }

  BetterPlayerSubtitle._({this.index, this.start, this.end, this.texts});

  static const String timerSeparator = ' --> ';
  final int? index;
  final Duration? start;
  final Duration? end;
  final List<String>? texts;

  static Duration _stringToDuration(String value) {
    try {
      final spaceSplit = value.trim().split(RegExp(r'\s+'));
      final cleanVal = spaceSplit.first.trim();

      final component = cleanVal.split(':');
      if (component.length == 2) {
        component.insert(0, '00');
      } else if (component.length != 3) {
        return Duration.zero;
      }

      final secsAndMillisSplitChar = component[2].contains(',') ? ',' : '.';
      final secsAndMillsSplit = component[2].split(secsAndMillisSplitChar);
      if (secsAndMillsSplit.length != 2) {
        return Duration.zero;
      }

      final hours = int.tryParse(component[0].trim()) ?? 0;
      final minutes = int.tryParse(component[1].trim()) ?? 0;
      final seconds = int.tryParse(secsAndMillsSplit[0].trim()) ?? 0;
      final millisRaw = secsAndMillsSplit[1].trim();
      final millisPadded = millisRaw.padRight(3, '0');
      final milliseconds = int.tryParse(
        millisPadded.length > 3 ? millisPadded.substring(0, 3) : millisPadded,
      ) ?? 0;

      return Duration(
        hours: hours,
        minutes: minutes,
        seconds: seconds,
        milliseconds: milliseconds,
      );
    } catch (e) {
      BetterPlayerUtils.log('Failed to process duration value: $value ($e)');
      return Duration.zero;
    }
  }

  @override
  String toString() => 'BetterPlayerSubtitle{index: $index, start: $start, end: $end, texts: $texts}';
}
