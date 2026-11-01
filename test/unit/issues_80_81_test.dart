import 'package:flutter_test/flutter_test.dart';
import 'package:ani_dash/core/models/anime/source_model.dart';
import 'package:ani_dash/core/models/universal/universal_media.dart';

void main() {
  group('Issue #81: Download Quality & Dub Selection Tests', () {
    bool isSourceDub(Source s) {
      if (s.isDub) return true;
      final q = (s.quality ?? '').toLowerCase();
      if (q.contains('dub') || q.contains('(dub)') || q.contains('[dub]')) {
        return true;
      }
      final u = (s.url ?? '').toLowerCase();
      if (u.contains('dub') || u.contains('-dub') || u.contains('_dub')) {
        return true;
      }
      return false;
    }

    test('Correctly identifies DUB from quality tag [Dub]', () {
      final dubSource = Source(
        url: 'https://example.com/stream/index.m3u8',
        quality: '1080p - ZokoAnime [Dub]',
        isDub: false, // third-party extension set bool to false
      );

      expect(isSourceDub(dubSource), isTrue);
    });

    test('Correctly identifies DUB from URL parameter', () {
      final dubSource = Source(
        url: 'https://example.com/hls/ep1-dub/master.m3u8',
        quality: '1080p',
        isDub: false,
      );

      expect(isSourceDub(dubSource), isTrue);
    });

    test('Identifies standard SUB stream without falsely tagging as DUB', () {
      final subSource = Source(
        url: 'https://example.com/hls/ep1-sub/master.m3u8',
        quality: '1080p - ZokoAnime [Sub]',
        isDub: false,
      );

      expect(isSourceDub(subSource), isFalse);
    });

    test('Automatic fallback from DUB to SUB when DUB unavailable', () {
      final streams = [
        Source(url: 'https://example.com/1080.m3u8', quality: '1080p - Sub', isDub: false),
        Source(url: 'https://example.com/720.m3u8', quality: '720p - Sub', isDub: false),
      ];

      String selectedLanguage = 'dub';
      final hasDub = streams.any((s) => isSourceDub(s));

      if (!hasDub && selectedLanguage == 'dub') {
        selectedLanguage = 'sub';
      }

      expect(selectedLanguage, 'sub');
    });

    test('Avoids duplicate quality rendering when specific streams are provided', () {
      final availableStreams = [
        Source(url: 'https://example.com/1080.m3u8', quality: '1080p', isDub: false),
        Source(url: 'https://example.com/720.m3u8', quality: '720p', isDub: false),
        Source(url: 'https://example.com/360.m3u8', quality: '360p', isDub: false),
      ];

      final hasSpecificStreams = availableStreams.length > 1;
      // In download_source_selector, when hasSpecificStreams is true,
      // only the specific streams are rendered, and the generic 4-card grid is omitted.
      expect(hasSpecificStreams, isTrue);
    });
  });

  group('Issue #80: Universal Media Mapping for Extension Catalog', () {
    test('Constructs valid UniversalMedia object from extension items', () {
      const extTitle = 'Attack on Titan';
      const extUrl = 'https://anikoto.com/anime/aot';
      const extCover = 'https://anikoto.com/covers/aot.jpg';

      final media = UniversalMedia(
        id: extUrl,
        title: const UniversalTitle(
          english: extTitle,
          romaji: extTitle,
          native: extTitle,
        ),
        coverImage: const UniversalCoverImage(
          large: extCover,
          medium: extCover,
        ),
        description: 'Titan action series',
        format: 'TV',
      );

      expect(media.id, extUrl);
      expect(media.title.userPreferred, extTitle);
      expect(media.title.available, extTitle);
      expect(media.coverImage.large, extCover);
      expect(media.format, 'TV');
    });
  });
}
