import 'package:ani_dash/core/models/settings/theme_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('navigation appearance settings', () {
    test('new installs keep blur and compact-on-scroll enabled', () {
      final settings = ThemeModel();
      expect(settings.navigationBlur, isTrue);
      expect(settings.compactNavigationOnScroll, isTrue);
    });

    test('toolbar preferences survive persistence', () {
      final restored = ThemeModel.fromMap(
        ThemeModel(
          navigationBlur: false,
          compactNavigationOnScroll: false,
        ).toMap(),
      );
      expect(restored.navigationBlur, isFalse);
      expect(restored.compactNavigationOnScroll, isFalse);
    });
  });
}
