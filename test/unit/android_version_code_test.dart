import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android version code stays monotonic and follows semantic version', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final match = RegExp(
      r'^version:\s*(\d+)\.(\d+)\.(\d+)\+(\d+)\s*$',
      multiLine: true,
    ).firstMatch(pubspec);

    expect(match, isNotNull, reason: 'pubspec.yaml must declare a build code');

    final major = int.parse(match!.group(1)!);
    final minor = int.parse(match.group(2)!);
    final patch = int.parse(match.group(3)!);
    final buildCode = int.parse(match.group(4)!);
    final semanticFloor = major * 1000000 + minor * 10000 + patch * 100;

    expect(
      buildCode,
      greaterThan(35400),
      reason: 'Existing v3.3.4 installations used Android build code 35400',
    );
    expect(
      buildCode,
      greaterThanOrEqualTo(semanticFloor),
      reason: 'Build codes must remain monotonic across semantic releases',
    );
  });
}
