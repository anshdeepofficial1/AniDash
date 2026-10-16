import 'package:ani_dash/core/utils/video_quality_label.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('provider labels expose only the actual resolution', () {
    expect(normalizeVideoQualityLabel('Mega Play Dub 1080p'), '1080p');
    expect(normalizeVideoQualityLabel('Mega Play Dub 720p'), '720p');
    expect(normalizeVideoQualityLabel('server 360'), '360p');
  });

  test('server names are not presented as quality choices', () {
    expect(normalizeVideoQualityLabel('Mega Play Dub'), 'Auto');
    expect(normalizeVideoQualityLabel('default'), 'Auto');
  });
}
