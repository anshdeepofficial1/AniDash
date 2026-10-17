import 'package:ani_dash/core/models/aniskip/aniskip_result.dart';
import 'package:ani_dash/features/watch/view_model/player/player_provider.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Episode transition state reset', () {
    test('PlayerState reset zeroes position, duration, and sets isOpening to true', () {
      // Simulate an episode that just finished (e.g. Ep 277 at 24:00)
      const finishedState = PlayerState(
        position: Duration(minutes: 24),
        duration: Duration(minutes: 24),
        buffer: Duration(minutes: 24),
        isPlaying: false,
        isBuffering: false,
        isSeeking: false,
        isOpening: false,
        playbackSpeed: 1.0,
        subtitle: [],
        fit: BoxFit.contain,
        fitMode: VideoFitMode.fitScreen,
        subtitleDelay: 0.0,
        isRepeating: false,
      );

      // Reset for next episode (e.g. Ep 278)
      final resetState = finishedState.copyWith(
        position: Duration.zero,
        duration: Duration.zero,
        buffer: Duration.zero,
        isOpening: true,
        isBuffering: true,
        clearPlaybackError: true,
      );

      expect(resetState.position, Duration.zero);
      expect(resetState.duration, Duration.zero);
      expect(resetState.buffer, Duration.zero);
      expect(resetState.isOpening, isTrue);
      expect(resetState.isBuffering, isTrue);
    });
  });

  group('AniSkip per-range key tracking on 10s seek', () {
    test('autoSkipRangeKey uniquely identifies intro and outro segments', () {
      const introItem = AniSkipResultItem(
        skipType: SkipType.op,
        interval: AniSkipInterval(startTime: 90, endTime: 180),
        action: 'skip',
        episodeLength: 1440,
      );

      const outroItem = AniSkipResultItem(
        skipType: SkipType.ed,
        interval: AniSkipInterval(startTime: 1300, endTime: 1390),
        action: 'skip',
        episodeLength: 1440,
      );

      final introKey =
          '${introItem.skipType.name}_${introItem.interval!.startTime.toInt()}_${introItem.interval!.endTime.toInt() + 1}';
      final outroKey =
          '${outroItem.skipType.name}_${outroItem.interval!.startTime.toInt()}_${outroItem.interval!.endTime.toInt() + 1}';

      expect(introKey, 'op_90_181');
      expect(outroKey, 'ed_1300_1391');
      expect(introKey, isNot(equals(outroKey)));

      final skippedKeys = <String>{};

      // Fast forward 10s into intro: position 95s
      const currentPos = Duration(seconds: 95);
      final start = Duration(seconds: introItem.interval!.startTime.toInt());
      final end = Duration(seconds: introItem.interval!.endTime.toInt() + 1);

      final shouldSkip = !skippedKeys.contains(introKey) &&
          currentPos >= start &&
          currentPos < end;

      expect(shouldSkip, isTrue);
      skippedKeys.add(introKey);

      // Once skipped, the same range is not repeatedly triggered
      final shouldSkipAgain = !skippedKeys.contains(introKey) &&
          currentPos >= start &&
          currentPos < end;
      expect(shouldSkipAgain, isFalse);

      // But outro key is unaffected and ready to be skipped
      expect(skippedKeys.contains(outroKey), isFalse);
    });
  });

  group('Next Episode Prompt 55-Second Threshold', () {
    test('Fallback prompt activates at 55 seconds when outro is absent', () {
      const durationSeconds = 1440; // 24-minute episode

      bool shouldTrigger(int currentPosition, bool hasDetectedOutro) {
        final remainingSeconds = durationSeconds - currentPosition;
        return hasDetectedOutro
            ? false
            : (remainingSeconds <= 55 && remainingSeconds > 0 && durationSeconds > 55);
      }

      // At 60 seconds remaining -> not yet triggered
      expect(shouldTrigger(1380, false), isFalse);

      // At exactly 55 seconds remaining -> triggered!
      expect(shouldTrigger(1385, false), isTrue);

      // At 30 seconds remaining -> triggered!
      expect(shouldTrigger(1410, false), isTrue);
    });
  });
}
