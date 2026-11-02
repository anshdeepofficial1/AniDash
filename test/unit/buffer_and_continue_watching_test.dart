import 'package:flutter_test/flutter_test.dart';
import 'package:ani_dash/data/hive/models/anime_watch_progress_model.dart';
import 'package:better_player_plus/better_player_plus.dart';

void main() {
  group('Player Forward Buffering Tests (>= 100 Seconds Buffer)', () {
    test('Default buffering configuration guarantees at least 100 seconds buffer', () {
      const config = BetterPlayerBufferingConfiguration();
      // 120 seconds minimum forward buffer (exceeds 100 seconds requirement)
      expect(config.minBufferMs, greaterThanOrEqualTo(100000));
      expect(config.minBufferMs, equals(120000));
      expect(config.maxBufferMs, equals(300000));
      expect(config.bufferForPlaybackMs, lessThanOrEqualTo(2000));
    });
  });

  group('Continue Watching Stability Tests', () {
    test('hasAnyWatchProgress returns true for active watching anime', () {
      final entry = AnimeWatchProgressEntry(
        animeId: '12345',
        animeTitle: 'Solo Leveling',
        animeFormat: 'TV',
        animeCover: 'https://example.com/cover.jpg',
        totalEpisodes: 12,
        lastUpdated: DateTime.now(),
        currentEpisode: 3,
        status: 'watching',
        episodesProgress: {
          3: EpisodeProgress(
            episodeNumber: 3,
            episodeTitle: 'Episode 3',
            episodeThumbnail: 'https://example.com/cover.jpg',
            progressInSeconds: 0,
            durationInSeconds: 1440,
            isCompleted: false,
          ),
        },
      );

      // Even with 0 seconds in current episode, an active watching anime must remain visible
      expect(entry.hasAnyWatchProgress, isTrue);
    });

    test('Completed episodes in episodesProgress qualify for hasAnyWatchProgress', () {
      final entry = AnimeWatchProgressEntry(
        animeId: '67890',
        animeTitle: 'Frieren',
        animeFormat: 'TV',
        animeCover: 'https://example.com/frieren.jpg',
        totalEpisodes: 28,
        lastUpdated: DateTime.now(),
        currentEpisode: 5,
        status: 'CURRENT',
        episodesProgress: {
          1: EpisodeProgress(
            episodeNumber: 1,
            episodeTitle: 'Episode 1',
            episodeThumbnail: 'https://example.com/frieren.jpg',
            progressInSeconds: 1440,
            durationInSeconds: 1440,
            isCompleted: true,
          ),
        },
      );

      expect(entry.hasAnyWatchProgress, isTrue);
    });
  });
}
