import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('player episode sheet reserves vertical gestures for its list', () {
    final source =
        File('lib/features/watch/view/watch_screen.dart').readAsStringSync();

    expect(source, contains('enableDrag: false'));
    expect(source, contains('child: EpisodesPanel('));
  });
}
