import 'package:ani_dash/core/utils/episode_source_routing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('EpisodeSourceRouting', () {
    test('keeps an explicitly selected extension authoritative', () {
      expect(
        EpisodeSourceRouting.shouldUseSelectedExtension(
          extensionsEnabled: true,
          hasActiveExtension: true,
        ),
        isTrue,
      );
    });

    test('does not use extensions when the feature is disabled', () {
      expect(
        EpisodeSourceRouting.shouldUseSelectedExtension(
          extensionsEnabled: false,
          hasActiveExtension: true,
        ),
        isFalse,
      );
    });

    test('does not use an extension when none is selected', () {
      expect(
        EpisodeSourceRouting.shouldUseSelectedExtension(
          extensionsEnabled: true,
          hasActiveExtension: false,
        ),
        isFalse,
      );
    });
  });
}
