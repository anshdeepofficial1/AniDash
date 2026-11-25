import 'package:flutter_test/flutter_test.dart';
import 'package:ani_dash/core/repositories/watch_progress_repository.dart';
import 'package:ani_dash/data/hive/models/anime_watch_progress_model.dart';

void main() {
  group('Bulk watched progress', () {
    test('marking through episode 455 persists completion and selects 456', () {
      final oldPlayTime = DateTime(2026, 11, 20, 12);
      final changedAt = DateTime(2026, 11, 25, 14);
      final existing = AnimeWatchProgressEntry(
        animeId: '21',
        animeTitle: 'One Piece',
        animeFormat: 'TV',
        animeCover: 'cover',
        totalEpisodes: 1180,
        currentEpisode: 450,
        lastPlayedAt: oldPlayTime,
        episodesProgress: {
          450: EpisodeProgress(
            episodeNumber: 450,
            episodeTitle: 'Before Marineford',
            episodeThumbnail: null,
            progressInSeconds: 600,
            durationInSeconds: 1440,
            isCompleted: false,
          ),
        },
      );

      final updated = mergeBulkWatchedProgress(
        existing: existing,
        animeId: '21',
        animeTitle: 'One Piece',
        animeCover: 'cover',
        animeFormat: 'TV',
        upToEpisodeNumber: 455,
        totalEpisodes: 1180,
        changedAt: changedAt,
      );

      expect(updated.currentEpisode, 456);
      expect(updated.status, 'watching');
      expect(updated.lastUpdated, changedAt);
      expect(updated.lastPlayedAt, oldPlayTime);
      expect(updated.episodesProgress.length, 455);
      for (var episode = 1; episode <= 455; episode++) {
        final progress = updated.episodesProgress[episode]!;
        expect(progress.isCompleted, isTrue);
        expect(progress.progressInSeconds, progress.durationInSeconds);
      }
      expect(updated.isCompletedOrFinished, isFalse);
      expect(updated.hasAnyWatchProgress, isTrue);
    });

    test('marking the final episode completes a finite series', () {
      final updated = mergeBulkWatchedProgress(
        animeId: 'series',
        animeTitle: 'Series',
        animeCover: '',
        animeFormat: 'TV',
        upToEpisodeNumber: 12,
        totalEpisodes: 12,
      );

      expect(updated.currentEpisode, 12);
      expect(updated.status, 'completed');
      expect(updated.isCompletedOrFinished, isTrue);
    });
  });
}
