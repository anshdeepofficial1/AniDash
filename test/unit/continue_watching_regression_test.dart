import 'package:flutter_test/flutter_test.dart';
import 'package:ani_dash/data/hive/models/anime_watch_progress_model.dart';
import 'package:ani_dash/core/utils/cloud_watch_progress_sync.dart';

void main() {
  group('Continue Watching regressions', () {
    test('unknown-length series stays visible after one watched episode', () {
      final entry = AnimeWatchProgressEntry(
        animeId: 'one-piece',
        animeTitle: 'One Piece',
        animeFormat: 'TV',
        animeCover: '',
        totalEpisodes: 0,
        currentEpisode: 182,
        episodesProgress: {
          182: EpisodeProgress(
            episodeNumber: 182,
            episodeTitle: 'Episode 182',
            episodeThumbnail: null,
            isCompleted: true,
            progressInSeconds: 1440,
            durationInSeconds: 1440,
          ),
        },
      );

      expect(entry.isCompletedOrFinished, isFalse);
      expect(entry.hasAnyWatchProgress, isTrue);
    });

    test('a completed one-shot movie leaves Continue Watching', () {
      final entry = AnimeWatchProgressEntry(
        animeId: 'movie',
        animeTitle: 'Movie',
        animeFormat: 'MOVIE',
        animeCover: '',
        totalEpisodes: 1,
        currentEpisode: 1,
        episodesProgress: {
          1: EpisodeProgress(
            episodeNumber: 1,
            episodeTitle: 'Movie',
            episodeThumbnail: null,
            isCompleted: true,
            progressInSeconds: 5400,
            durationInSeconds: 5400,
          ),
        },
      );

      expect(entry.isCompletedOrFinished, isTrue);
    });

    test('18 of 23 minutes remains on the current episode after refresh', () {
      final progress = EpisodeProgress(
        episodeNumber: 1,
        episodeTitle: 'Episode 1',
        episodeThumbnail: null,
        // A legacy build could have stored true at the old 90% threshold.
        // Known timing data is authoritative and must repair that state.
        isCompleted: true,
        progressInSeconds: 18 * 60,
        durationInSeconds: 23 * 60,
      );

      expect(isEpisodeProgressEffectivelyComplete(progress), isFalse);
    });

    test('temporary HLS segment duration cannot complete an episode', () {
      expect(
        isPlaybackEffectivelyComplete(
          progressInSeconds: 8,
          durationInSeconds: 8,
        ),
        isFalse,
      );
    });

    test('episode completes only at its real end', () {
      expect(
        isPlaybackEffectivelyComplete(
          progressInSeconds: 22 * 60 + 45,
          durationInSeconds: 23 * 60,
        ),
        isTrue,
      );
    });

    test('remote EP4 progress advances stale local notes to EP5', () {
      expect(
        CloudWatchProgressSync.resolveContinueEpisode(
          trackerProgress: 4,
          notesEpisode: 2,
          notesSeconds: 600,
          notesDuration: 1440,
          totalEpisodes: 12,
        ),
        5,
      );
    });

    test('partial next episode from tracker notes is preserved', () {
      expect(
        CloudWatchProgressSync.resolveContinueEpisode(
          trackerProgress: 4,
          notesEpisode: 5,
          notesSeconds: 600,
          notesDuration: 1440,
          totalEpisodes: 12,
        ),
        5,
      );
    });

    test('completed tracker series does not advance beyond final episode', () {
      expect(
        CloudWatchProgressSync.resolveContinueEpisode(
          trackerProgress: 12,
          totalEpisodes: 12,
        ),
        12,
      );
    });
  });
}
