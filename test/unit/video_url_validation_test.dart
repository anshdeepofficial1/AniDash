import 'package:flutter_test/flutter_test.dart';
import 'package:ani_dash/core/utils/video_utils.dart';

void main() {
  group('VideoUtils.isValidNetworkUrl', () {
    test('accepts complete HTTP and HTTPS media URLs', () {
      expect(
        VideoUtils.isValidNetworkUrl('https://cdn.example.com/video.m3u8'),
        isTrue,
      );
      expect(
        VideoUtils.isValidNetworkUrl('http://media.example.com/file.mp4'),
        isTrue,
      );
    });

    test('rejects missing, relative, and hostless URLs', () {
      expect(VideoUtils.isValidNetworkUrl(null), isFalse);
      expect(VideoUtils.isValidNetworkUrl(''), isFalse);
      expect(VideoUtils.isValidNetworkUrl('/episode/video.m3u8'), isFalse);
      expect(VideoUtils.isValidNetworkUrl('https:///video.m3u8'), isFalse);
      expect(VideoUtils.isValidNetworkUrl('file:///video.mp4'), isFalse);
    });
  });
}
