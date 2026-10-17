import 'package:ani_dash/core/models/aniskip/aniskip_result.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('episode-specific skip marker parsing', () {
    Map<String, Object?> marker(String type) => {
      'skipType': type,
      'interval': {'startTime': 10, 'endTime': 100},
      'episodeLength': 1440,
    };

    test('mixed opening remains an opening marker', () {
      expect(
        AniSkipResultItem.fromJson(marker('mixed-op')).skipType,
        SkipType.op,
      );
    });

    test('mixed ending remains an ending marker', () {
      expect(
        AniSkipResultItem.fromJson(marker('mixed-ed')).skipType,
        SkipType.ed,
      );
    });

    test('recap remains independent from intro and outro', () {
      expect(
        AniSkipResultItem.fromJson(marker('recap')).skipType,
        SkipType.recap,
      );
    });
  });
}
