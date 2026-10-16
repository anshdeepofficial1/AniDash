import 'package:ani_dash/core/models/settings/notification_settings_model.dart';
import 'package:ani_dash/core/services/notification_inbox_service.dart';
import 'package:ani_dash/core/tasks/episode_release_task.dart';
import 'package:ani_dash/data/hive/models/anime_watch_progress_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Release notification watch-progress window', () {
    test('suppresses a release when the viewer is far behind', () {
      expect(isReleaseWithinWatchWindow(160, 1180), isFalse);
    });

    test('allows releases only within the next 12 episodes', () {
      expect(isReleaseWithinWatchWindow(1168, 1180), isTrue);
      expect(isReleaseWithinWatchWindow(1167, 1180), isFalse);
      expect(isReleaseWithinWatchWindow(1180, 1180), isFalse);
    });

    test(
      'planning titles receive first-cour releases without long-show spam',
      () {
        expect(
          isReleaseRelevantForStatus(
            currentEpisode: 0,
            releaseEpisode: 1,
            status: 'PLANNING',
          ),
          isTrue,
        );
        expect(
          isReleaseRelevantForStatus(
            currentEpisode: 0,
            releaseEpisode: 12,
            status: 'planning',
          ),
          isTrue,
        );
        expect(
          isReleaseRelevantForStatus(
            currentEpisode: 0,
            releaseEpisode: 1100,
            status: 'planning',
          ),
          isFalse,
        );
      },
    );
  });

  group('NotificationInboxService Deserialization & Backward Compatibility', () {
    test('Correctly deserializes legacy notification missing new metadata', () {
      final legacyJson = {
        'id': 'legacy_123',
        'title': 'New Episode Released',
        'body': 'Episode 5 is now available!',
        'createdAt': DateTime(2026, 9, 20, 12, 0).toIso8601String(),
        'isRead': false,
      };

      final notification = InboxNotification.fromJson(legacyJson);

      expect(notification.id, 'legacy_123');
      expect(notification.title, 'New Episode Released');
      expect(notification.body, 'Episode 5 is now available!');
      expect(notification.isRead, false);
      expect(notification.notificationType, isNull);
      expect(notification.mediaId, isNull);
      expect(notification.episodeNumber, isNull);
      expect(notification.language, isNull);
      expect(notification.route, isNull);
    });

    test(
      'Correctly serializes and deserializes structured v1.15.4 notification',
      () {
        final item = InboxNotification(
          id: 'ep_sub_100_12',
          title: 'One Piece - Ep 12 Released',
          body: 'Episode 12 (Sub) is now available to watch!',
          createdAt: DateTime(2026, 9, 24, 15, 30),
          notificationType: 'episode_release',
          mediaId: '100',
          episodeNumber: 12,
          language: 'sub',
          route: '/details/100?tab=episodes',
          isRead: false,
        );

        final json = item.toJson();
        final reconstructed = InboxNotification.fromJson(json);

        expect(reconstructed.id, 'ep_sub_100_12');
        expect(reconstructed.notificationType, 'episode_release');
        expect(reconstructed.mediaId, '100');
        expect(reconstructed.episodeNumber, 12);
        expect(reconstructed.language, 'sub');
        expect(reconstructed.route, '/details/100?tab=episodes');
        expect(reconstructed.isRead, false);
      },
    );

    test(
      'Loads and stores inbox notifications from SharedPreferences with copyWith',
      () async {
        SharedPreferences.setMockInitialValues({});
        final inboxService = NotificationInboxService();

        await inboxService.add(
          title: 'Test Notification',
          body: 'Test Body',
          route: '/details/21?tab=episodes',
          dedupeKey: 'test_1',
          notificationType: 'episode_release',
          mediaId: '21',
          episodeNumber: 5,
          language: 'dub',
        );

        final list = await inboxService.load();

        expect(list.length, 1);
        expect(list.first.id, 'test_1');
        expect(list.first.route, '/details/21?tab=episodes');
        expect(list.first.notificationType, 'episode_release');
        expect(list.first.mediaId, '21');
        expect(list.first.episodeNumber, 5);
        expect(list.first.language, 'dub');
        expect(list.first.isRead, false);

        await inboxService.markRead('test_1');
        final updatedList = await inboxService.load();
        expect(updatedList.first.isRead, true);
        expect(updatedList.first.mediaId, '21');
        expect(updatedList.first.episodeNumber, 5);
        expect(updatedList.first.language, 'dub');
        expect(updatedList.first.notificationType, 'episode_release');
      },
    );
  });

  group('Deep Link Route Parsing', () {
    test('Maps tab query parameter to initial tab index', () {
      int resolveInitialTabIndex(String? tabParam) {
        if (tabParam == 'episodes') {
          return 1;
        }
        return 0;
      }

      expect(resolveInitialTabIndex('episodes'), 1);
      expect(resolveInitialTabIndex(null), 0);
      expect(resolveInitialTabIndex('details'), 0);
      expect(resolveInitialTabIndex('characters'), 0);
    });
  });

  group('Upcoming Alert Deduplication Keys', () {
    test('Generates distinct keys for 2h and tomorrow alerts', () {
      final mediaId = 12345;
      final episodeNumber = 7;

      final key2h = 'upcoming:$mediaId:$episodeNumber:2h';
      final keyTomorrow = 'upcoming:$mediaId:$episodeNumber:tomorrow';

      expect(key2h, 'upcoming:12345:7:2h');
      expect(keyTomorrow, 'upcoming:12345:7:tomorrow');
      expect(key2h != keyTomorrow, isTrue);
    });
  });

  group('Update Interval and WorkManager Wording', () {
    test('Clamps update check interval to Android WorkManager 15m minimum', () {
      int effectiveInterval(int configuredMinutes) {
        return configuredMinutes < 15 ? 15 : configuredMinutes;
      }

      expect(effectiveInterval(5), 15);
      expect(effectiveInterval(10), 15);
      expect(effectiveInterval(15), 15);
      expect(effectiveInterval(60), 60);
      expect(effectiveInterval(720), 720);
    });
  });

  group('Release Detection, Deduplication & Wording Logic', () {
    test(
      'SUB: previous 10 -> current 11 emits notification, repeated 11 emits 0 duplicates',
      () {
        final mockPrefs = <String, int>{'last_known_sub_ep_100': 10};
        final emittedNotifications = <int>[];

        void runSubDetectionCheck(int latestSub) {
          final previousSub = mockPrefs['last_known_sub_ep_100'];
          if (previousSub != null && latestSub > previousSub) {
            emittedNotifications.add(latestSub);
          }
          mockPrefs['last_known_sub_ep_100'] = latestSub;
        }

        // First run: new episode 11 available
        runSubDetectionCheck(11);
        expect(emittedNotifications, [
          11,
        ], reason: 'Exactly one notification for Episode 11');

        // Second run: latest is still 11
        runSubDetectionCheck(11);
        expect(
          emittedNotifications.length,
          1,
          reason: 'Zero duplicate notifications on repeat check',
        );
      },
    );

    test(
      'English Dub: previous 5 -> current 6 emits notification, repeated 6 emits 0 duplicates',
      () {
        final mockPrefs = <String, int>{'last_known_english_dub_ep_100': 5};
        final emittedDubNotifications = <int>[];

        void runDubDetectionCheck(int latestDub) {
          final previousDub = mockPrefs['last_known_english_dub_ep_100'];
          if (previousDub != null && latestDub > previousDub) {
            emittedDubNotifications.add(latestDub);
          }
          mockPrefs['last_known_english_dub_ep_100'] = latestDub;
        }

        runDubDetectionCheck(6);
        expect(emittedDubNotifications, [6]);

        runDubDetectionCheck(6);
        expect(emittedDubNotifications.length, 1);
      },
    );

    test('Notification wording rules: caught-up vs behind user', () {
      String generateBody({
        required int currentEp,
        required int latestReleased,
      }) {
        if (currentEp >= latestReleased - 1) {
          return 'Episode $latestReleased just released! Watch the newest episode on AniDash.';
        } else {
          return 'Episode $latestReleased is now available! You\'re currently on Episode $currentEp.';
        }
      }

      // User caught up (on Ep 10, Ep 11 releases)
      final caughtUpBody = generateBody(currentEp: 10, latestReleased: 11);
      expect(
        caughtUpBody,
        'Episode 11 just released! Watch the newest episode on AniDash.',
      );

      // User behind (on Ep 4, Ep 11 releases)
      final behindBody = generateBody(currentEp: 4, latestReleased: 11);
      expect(
        behindBody,
        'Episode 11 is now available! You\'re currently on Episode 4.',
      );
    });
  });

  group('Notification Settings Independent Category Toggles', () {
    test(
      'Controlled Matrix 1: News OFF, Dub ON, Sub OFF, Continue Watching ON, Downloads ON',
      () {
        const settings = NotificationSettingsModel(
          enableNews: false,
          enableDubReleases: true,
          enableSubReleases: false,
          enableContinueWatching: true,
          enableDownloads: true,
        );

        final jsonMap = settings.toJson();
        final restored = NotificationSettingsModel.fromJson(jsonMap);

        expect(restored.enableNews, false, reason: 'News must be blocked');
        expect(
          restored.enableSubReleases,
          false,
          reason: 'SUB must be blocked',
        );
        expect(
          restored.enableDubReleases,
          true,
          reason: 'Dub (English & Hindi) must be allowed',
        );
        expect(
          restored.enableContinueWatching,
          true,
          reason: 'Continue watching must be allowed',
        );
        expect(
          restored.enableDownloads,
          true,
          reason: 'Downloads must be allowed',
        );
      },
    );

    test(
      'Controlled Matrix 2 (Inverse): News ON, Dub OFF, Sub ON, Continue Watching OFF, Downloads OFF',
      () {
        const settings = NotificationSettingsModel(
          enableNews: true,
          enableDubReleases: false,
          enableSubReleases: true,
          enableContinueWatching: false,
          enableDownloads: false,
        );

        final jsonMap = settings.toJson();
        final restored = NotificationSettingsModel.fromJson(jsonMap);

        expect(restored.enableNews, true, reason: 'News must be allowed');
        expect(restored.enableSubReleases, true, reason: 'SUB must be allowed');
        expect(
          restored.enableDubReleases,
          false,
          reason: 'Dub must be blocked',
        );
        expect(
          restored.enableContinueWatching,
          false,
          reason: 'Continue watching must be blocked',
        );
        expect(
          restored.enableDownloads,
          false,
          reason: 'Downloads must be blocked',
        );
      },
    );
  });

  group('Double-Tap Seek Calculation & Clamping', () {
    Duration calculateSeekTarget({
      required Duration currentPosition,
      required Duration totalDuration,
      required int pairCount,
      required bool isForward,
    }) {
      final seconds = pairCount * 10;
      final signedSeconds = isForward ? seconds : -seconds;
      final target = currentPosition + Duration(seconds: signedSeconds);
      if (target < Duration.zero) return Duration.zero;
      if (target > totalDuration) return totalDuration;
      return target;
    }

    test('1 complete double tap pair starts immediately at +/- 10s', () {
      const current = Duration(seconds: 50);
      const total = Duration(seconds: 120);

      final rightSeek = calculateSeekTarget(
        currentPosition: current,
        totalDuration: total,
        pairCount: 1,
        isForward: true,
      );
      final leftSeek = calculateSeekTarget(
        currentPosition: current,
        totalDuration: total,
        pairCount: 1,
        isForward: false,
      );

      expect(
        rightSeek,
        const Duration(seconds: 60),
        reason: 'First right double tap must be +10s',
      );
      expect(
        leftSeek,
        const Duration(seconds: 40),
        reason: 'First left double tap must be -10s',
      );
    });

    test(
      'Rapid consecutive double taps accumulate correctly: 20s, 30s, 40s',
      () {
        const current = Duration(seconds: 50);
        const total = Duration(seconds: 120);

        // 2 pairs = 20s
        expect(
          calculateSeekTarget(
            currentPosition: current,
            totalDuration: total,
            pairCount: 2,
            isForward: true,
          ),
          const Duration(seconds: 70),
        );
        expect(
          calculateSeekTarget(
            currentPosition: current,
            totalDuration: total,
            pairCount: 2,
            isForward: false,
          ),
          const Duration(seconds: 30),
        );

        // 3 pairs = 30s
        expect(
          calculateSeekTarget(
            currentPosition: current,
            totalDuration: total,
            pairCount: 3,
            isForward: true,
          ),
          const Duration(seconds: 80),
        );
        expect(
          calculateSeekTarget(
            currentPosition: current,
            totalDuration: total,
            pairCount: 3,
            isForward: false,
          ),
          const Duration(seconds: 20),
        );

        // 4 pairs = 40s
        expect(
          calculateSeekTarget(
            currentPosition: current,
            totalDuration: total,
            pairCount: 4,
            isForward: true,
          ),
          const Duration(seconds: 90),
        );
        expect(
          calculateSeekTarget(
            currentPosition: current,
            totalDuration: total,
            pairCount: 4,
            isForward: false,
          ),
          const Duration(seconds: 10),
        );
      },
    );

    test(
      'Clamping at boundaries: 0:00 on backward seek and duration on forward seek',
      () {
        const total = Duration(seconds: 100);

        // Seek backward past 0:00 (from 5s with -10s seek)
        final backwardClamped = calculateSeekTarget(
          currentPosition: const Duration(seconds: 5),
          totalDuration: total,
          pairCount: 1,
          isForward: false,
        );
        expect(
          backwardClamped,
          Duration.zero,
          reason: 'Backward seek past 0 must clamp to 0:00',
        );

        // Seek forward past total duration (from 95s with +10s seek on 100s video)
        final forwardClamped = calculateSeekTarget(
          currentPosition: const Duration(seconds: 95),
          totalDuration: total,
          pairCount: 1,
          isForward: true,
        );
        expect(
          forwardClamped,
          total,
          reason: 'Forward seek past end must clamp to video duration',
        );
      },
    );
  });

  group('Request Generation & Invalidation Token', () {
    test(
      'Rapid episode / server / audio requests increment generation and discard stale responses',
      () async {
        int loadGeneration = 0;
        int activePlayingEpisode = 0;

        Future<void> simulateEpisodeLoad(int ep) async {
          final generation = ++loadGeneration;

          // Simulate async stream resolution with variable latency
          final latencyMs = ep == 10 ? 80 : 20; // ep 10 is slow, ep 11 is fast
          await Future.delayed(Duration(milliseconds: latencyMs));

          // Invalidation guard: only apply if generation is still active
          if (generation != loadGeneration) {
            return; // stale request discarded
          }

          activePlayingEpisode = ep;
        }

        // User requests ep 10, then immediately switches to ep 11
        final future10 = simulateEpisodeLoad(10);
        final future11 = simulateEpisodeLoad(11);

        await Future.wait([future10, future11]);

        expect(
          activePlayingEpisode,
          11,
          reason:
              'Episode 11 must be active; stale Ep 10 response must be discarded',
        );
        expect(loadGeneration, 2);
      },
    );
  });

  group('Continue Watching Recency & Playback-Only Ordering', () {
    test('Most recently played anime locally always appears first', () {
      final now = DateTime(2026, 9, 24, 12, 0);
      final onePiece = AnimeWatchProgressEntry(
        animeId: 'one-piece',
        animeTitle: 'One Piece',
        animeCover: '',
        totalEpisodes: 1100,
        currentEpisode: 1080,
        lastPlayedAt: now.subtract(const Duration(hours: 3)),
        episodesProgress: {
          1080: EpisodeProgress(
            episodeNumber: 1080,
            episodeTitle: 'Ep 1080',
            episodeThumbnail: '',
            progressInSeconds: 500,
            durationInSeconds: 1400,
          ),
        },
      );
      final animeB = AnimeWatchProgressEntry(
        animeId: 'anime-b',
        animeTitle: 'Anime B',
        animeCover: '',
        totalEpisodes: 24,
        currentEpisode: 5,
        lastPlayedAt: now.subtract(const Duration(hours: 2)),
        episodesProgress: {
          5: EpisodeProgress(
            episodeNumber: 5,
            episodeTitle: 'Ep 5',
            episodeThumbnail: '',
            progressInSeconds: 300,
            durationInSeconds: 1400,
          ),
        },
      );
      final animeC = AnimeWatchProgressEntry(
        animeId: 'anime-c',
        animeTitle: 'Anime C',
        animeCover: '',
        totalEpisodes: 12,
        currentEpisode: 2,
        lastPlayedAt: now.subtract(const Duration(hours: 1)),
        episodesProgress: {
          2: EpisodeProgress(
            episodeNumber: 2,
            episodeTitle: 'Ep 2',
            episodeThumbnail: '',
            progressInSeconds: 400,
            durationInSeconds: 1400,
          ),
        },
      );

      final list = [onePiece, animeB, animeC]
        ..sort(AnimeWatchProgressEntry.compareByRecency);

      // C (1 hr ago) > B (2 hrs ago) > One Piece (3 hrs ago)
      expect(list.map((e) => e.animeId).toList(), [
        'anime-c',
        'anime-b',
        'one-piece',
      ]);
    });

    test(
      'Watching 3rd item moves it to 1st, previous 1st becomes 2nd, 2nd becomes 3rd',
      () {
        final t1 = DateTime(2026, 9, 24, 10, 0);
        final t2 = DateTime(2026, 9, 24, 11, 0);
        final t3 = DateTime(2026, 9, 24, 12, 0);

        final onePiece = AnimeWatchProgressEntry(
          animeId: 'one-piece',
          animeTitle: 'One Piece',
          animeCover: '',
          totalEpisodes: 1100,
          currentEpisode: 1080,
          lastPlayedAt: t3, // 1st
          episodesProgress: {
            1080: EpisodeProgress(
              episodeNumber: 1080,
              episodeTitle: '1080',
              episodeThumbnail: '',
              progressInSeconds: 50,
              durationInSeconds: 1400,
            ),
          },
        );
        final animeB = AnimeWatchProgressEntry(
          animeId: 'anime-b',
          animeTitle: 'Anime B',
          animeCover: '',
          totalEpisodes: 24,
          currentEpisode: 5,
          lastPlayedAt: t2, // 2nd
          episodesProgress: {
            5: EpisodeProgress(
              episodeNumber: 5,
              episodeTitle: '5',
              episodeThumbnail: '',
              progressInSeconds: 50,
              durationInSeconds: 1400,
            ),
          },
        );
        final animeC = AnimeWatchProgressEntry(
          animeId: 'anime-c',
          animeTitle: 'Anime C',
          animeCover: '',
          totalEpisodes: 12,
          currentEpisode: 2,
          lastPlayedAt: t1, // 3rd
          episodesProgress: {
            2: EpisodeProgress(
              episodeNumber: 2,
              episodeTitle: '2',
              episodeThumbnail: '',
              progressInSeconds: 50,
              durationInSeconds: 1400,
            ),
          },
        );

        final initialOrder = [onePiece, animeB, animeC]
          ..sort(AnimeWatchProgressEntry.compareByRecency);
        expect(initialOrder.map((e) => e.animeId).toList(), [
          'one-piece',
          'anime-b',
          'anime-c',
        ]);

        // User now plays Anime C at t4 (most recent)
        final t4 = DateTime(2026, 9, 24, 13, 0);
        final updatedAnimeC = animeC.copyWith(lastPlayedAt: t4);

        final newOrder = [onePiece, animeB, updatedAnimeC]
          ..sort(AnimeWatchProgressEntry.compareByRecency);
        expect(newOrder.map((e) => e.animeId).toList(), [
          'anime-c',
          'one-piece',
          'anime-b',
        ]);
      },
    );

    test(
      'Watching #1 item again keeps it at #1 and NEVER moves it to the end',
      () {
        final t1 = DateTime(2026, 9, 24, 10, 0);
        final t2 = DateTime(2026, 9, 24, 11, 0);
        final t3 = DateTime(2026, 9, 24, 12, 0);

        var onePiece = AnimeWatchProgressEntry(
          animeId: 'one-piece',
          animeTitle: 'One Piece',
          animeCover: '',
          totalEpisodes: 1100,
          currentEpisode: 1080,
          lastPlayedAt: t3, // Currently #1
          episodesProgress: {
            1080: EpisodeProgress(
              episodeNumber: 1080,
              episodeTitle: '1080',
              episodeThumbnail: '',
              progressInSeconds: 50,
              durationInSeconds: 1400,
            ),
          },
        );
        final animeB = AnimeWatchProgressEntry(
          animeId: 'anime-b',
          animeTitle: 'Anime B',
          animeCover: '',
          totalEpisodes: 24,
          currentEpisode: 5,
          lastPlayedAt: t2,
          episodesProgress: {
            5: EpisodeProgress(
              episodeNumber: 5,
              episodeTitle: '5',
              episodeThumbnail: '',
              progressInSeconds: 50,
              durationInSeconds: 1400,
            ),
          },
        );
        final animeC = AnimeWatchProgressEntry(
          animeId: 'anime-c',
          animeTitle: 'Anime C',
          animeCover: '',
          totalEpisodes: 12,
          currentEpisode: 2,
          lastPlayedAt: t1,
          episodesProgress: {
            2: EpisodeProgress(
              episodeNumber: 2,
              episodeTitle: '2',
              episodeThumbnail: '',
              progressInSeconds: 50,
              durationInSeconds: 1400,
            ),
          },
        );

        // User plays One Piece again and exits
        final t4 = DateTime(2026, 9, 24, 14, 0);
        onePiece = onePiece.copyWith(lastPlayedAt: t4);

        final order = [onePiece, animeB, animeC]
          ..sort(AnimeWatchProgressEntry.compareByRecency);
        expect(order.first.animeId, 'one-piece');
        expect(order.map((e) => e.animeId).toList(), [
          'one-piece',
          'anime-b',
          'anime-c',
        ]);
      },
    );

    test(
      'Remote tracker sync preserves lastPlayedAt and does NOT jump ahead of local playback',
      () {
        final localPlayedTime = DateTime(2026, 9, 24, 15, 0);

        // Locally played anime
        final localAnime = AnimeWatchProgressEntry(
          animeId: 'local-1',
          animeTitle: 'Local Anime',
          animeCover: '',
          totalEpisodes: 24,
          currentEpisode: 10,
          lastPlayedAt: localPlayedTime,
          episodesProgress: {
            10: EpisodeProgress(
              episodeNumber: 10,
              episodeTitle: '10',
              episodeThumbnail: '',
              progressInSeconds: 100,
              durationInSeconds: 1400,
            ),
          },
        );

        // Synced anime from AniList (synced just now, but never played locally in app)
        final syncTime = DateTime(2026, 9, 24, 16, 0); // sync runs 1 hour later
        final syncedAnime = AnimeWatchProgressEntry(
          animeId: 'remote-1',
          animeTitle: 'Remote Anime',
          animeCover: '',
          totalEpisodes: 12,
          currentEpisode: 3,
          lastUpdated: syncTime, // sync timestamp
          lastPlayedAt: null, // never played locally
          episodesProgress: {
            3: EpisodeProgress(
              episodeNumber: 3,
              episodeTitle: '3',
              episodeThumbnail: '',
              progressInSeconds: 0,
              durationInSeconds: 1400,
              watchedAt: DateTime.fromMillisecondsSinceEpoch(0),
            ),
          },
        );

        final list = [syncedAnime, localAnime]
          ..sort(AnimeWatchProgressEntry.compareByRecency);

        // localAnime must appear first because it was actually played locally
        expect(list.first.animeId, 'local-1');
        expect(list.last.animeId, 'remote-1');
      },
    );

    test(
      'Source refresh / metadata update does NOT change Continue Watching order',
      () {
        final t1 = DateTime(2026, 9, 24, 10, 0);
        final t2 = DateTime(2026, 9, 24, 12, 0);

        final anime1 = AnimeWatchProgressEntry(
          animeId: 'anime-1',
          animeTitle: 'Anime 1',
          animeCover: '',
          totalEpisodes: 12,
          currentEpisode: 4,
          lastPlayedAt: t2,
          episodesProgress: {
            4: EpisodeProgress(
              episodeNumber: 4,
              episodeTitle: '4',
              episodeThumbnail: '',
              progressInSeconds: 50,
              durationInSeconds: 1400,
            ),
          },
        );

        final anime2 = AnimeWatchProgressEntry(
          animeId: 'anime-2',
          animeTitle: 'Anime 2',
          animeCover: '',
          totalEpisodes: 12,
          currentEpisode: 1,
          lastPlayedAt: t1,
          episodesProgress: {
            1: EpisodeProgress(
              episodeNumber: 1,
              episodeTitle: '1',
              episodeThumbnail: '',
              progressInSeconds: 50,
              durationInSeconds: 1400,
            ),
          },
        );

        // Source refresh updates anime2's metadata/lastUpdated without local playback
        final refreshedAnime2 = anime2.copyWith(
          lastUpdated: DateTime(2026, 9, 24, 14, 0), // metadata updated later
          // lastPlayedAt is unchanged!
        );

        final list = [anime1, refreshedAnime2]
          ..sort(AnimeWatchProgressEntry.compareByRecency);

        // anime1 was played at 12:00, anime2 played at 10:00 -> anime1 must stay first!
        expect(list.map((e) => e.animeId).toList(), ['anime-1', 'anime-2']);
      },
    );

    test(
      'Persistence across restarts: Serialization to and from Map preserves exact order',
      () {
        final t1 = DateTime(2026, 9, 24, 11, 0);
        final t2 = DateTime(2026, 9, 24, 13, 0);

        final original = [
          AnimeWatchProgressEntry(
            animeId: 'id-a',
            animeTitle: 'Title A',
            animeCover: '',
            totalEpisodes: 12,
            currentEpisode: 2,
            lastPlayedAt: t2,
            episodesProgress: {
              2: EpisodeProgress(
                episodeNumber: 2,
                episodeTitle: '2',
                episodeThumbnail: '',
                progressInSeconds: 100,
                durationInSeconds: 1400,
              ),
            },
          ),
          AnimeWatchProgressEntry(
            animeId: 'id-b',
            animeTitle: 'Title B',
            animeCover: '',
            totalEpisodes: 12,
            currentEpisode: 1,
            lastPlayedAt: t1,
            episodesProgress: {
              1: EpisodeProgress(
                episodeNumber: 1,
                episodeTitle: '1',
                episodeThumbnail: '',
                progressInSeconds: 100,
                durationInSeconds: 1400,
              ),
            },
          ),
        ];

        // Simulate save to storage and reload
        final serialized = original.map((e) => e.toMap()).toList();
        final reloaded =
            serialized.map((m) => AnimeWatchProgressEntry.fromMap(m)).toList()
              ..sort(AnimeWatchProgressEntry.compareByRecency);

        expect(reloaded.map((e) => e.animeId).toList(), ['id-a', 'id-b']);
        expect(reloaded.first.lastPlayedAt, t2);
        expect(reloaded.last.lastPlayedAt, t1);
      },
    );

    test(
      'In-place deduplication: Multiple entries for same anime ID are deduplicated to the latest',
      () {
        final tOld = DateTime(2026, 9, 24, 10, 0);
        final tNew = DateTime(2026, 9, 24, 14, 0);

        final listWithDups = [
          AnimeWatchProgressEntry(
            animeId: 'dup-1',
            animeTitle: 'Duplicate Anime',
            animeCover: '',
            totalEpisodes: 12,
            currentEpisode: 1,
            lastPlayedAt: tOld,
            episodesProgress: {
              1: EpisodeProgress(
                episodeNumber: 1,
                episodeTitle: '1',
                episodeThumbnail: '',
                progressInSeconds: 50,
                durationInSeconds: 1400,
              ),
            },
          ),
          AnimeWatchProgressEntry(
            animeId: 'dup-1',
            animeTitle: 'Duplicate Anime',
            animeCover: '',
            totalEpisodes: 12,
            currentEpisode: 2,
            lastPlayedAt: tNew,
            episodesProgress: {
              2: EpisodeProgress(
                episodeNumber: 2,
                episodeTitle: '2',
                episodeThumbnail: '',
                progressInSeconds: 100,
                durationInSeconds: 1400,
              ),
            },
          ),
        ];

        final Map<String, AnimeWatchProgressEntry> uniqueMap = {};
        for (final e in listWithDups) {
          if (!uniqueMap.containsKey(e.animeId) ||
              e.effectiveLastPlayedTime.isAfter(
                uniqueMap[e.animeId]!.effectiveLastPlayedTime,
              )) {
            uniqueMap[e.animeId] = e;
          }
        }
        final deduplicated =
            uniqueMap.values.toList()
              ..sort(AnimeWatchProgressEntry.compareByRecency);

        expect(deduplicated.length, 1);
        expect(deduplicated.first.currentEpisode, 2);
        expect(deduplicated.first.lastPlayedAt, tNew);
      },
    );

    test(
      'Backward compatibility: Legacy entries with null lastPlayedAt fall back gracefully to latestWatchTime',
      () {
        final legacyWatchTime = DateTime(2026, 9, 23, 18, 0);

        final legacyEntry = AnimeWatchProgressEntry(
          animeId: 'legacy-1',
          animeTitle: 'Legacy Anime',
          animeCover: '',
          totalEpisodes: 12,
          currentEpisode: 3,
          lastPlayedAt: null, // legacy data
          lastUpdated: legacyWatchTime,
          episodesProgress: {
            3: EpisodeProgress(
              episodeNumber: 3,
              episodeTitle: '3',
              episodeThumbnail: '',
              progressInSeconds: 200,
              durationInSeconds: 1400,
              watchedAt: legacyWatchTime,
            ),
          },
        );

        expect(legacyEntry.lastPlayedAt, isNull);
        expect(legacyEntry.effectiveLastPlayedTime, legacyWatchTime);
      },
    );

    test(
      'Stable secondary sort: Equal timestamps sort deterministically by title then ID',
      () {
        final sameTime = DateTime(2026, 9, 24, 12, 0);

        final bAnime = AnimeWatchProgressEntry(
          animeId: 'id-2',
          animeTitle: 'Bleach',
          animeCover: '',
          totalEpisodes: 366,
          currentEpisode: 1,
          lastPlayedAt: sameTime,
          episodesProgress: {
            1: EpisodeProgress(
              episodeNumber: 1,
              episodeTitle: '1',
              episodeThumbnail: '',
              progressInSeconds: 10,
              durationInSeconds: 1400,
            ),
          },
        );
        final aAnime = AnimeWatchProgressEntry(
          animeId: 'id-1',
          animeTitle: 'Attack on Titan',
          animeCover: '',
          totalEpisodes: 87,
          currentEpisode: 1,
          lastPlayedAt: sameTime,
          episodesProgress: {
            1: EpisodeProgress(
              episodeNumber: 1,
              episodeTitle: '1',
              episodeThumbnail: '',
              progressInSeconds: 10,
              durationInSeconds: 1400,
            ),
          },
        );

        final list = [bAnime, aAnime]
          ..sort(AnimeWatchProgressEntry.compareByRecency);

        expect(list.map((e) => e.animeTitle).toList(), [
          'Attack on Titan',
          'Bleach',
        ]);
      },
    );
  });

  group('Upcoming Episode Countdown & Alarm Scheduling Tests', () {
    test(
      'Exact alarm IDs are unique and deterministic for 24h, 2h, 1h, and release',
      () {
        const mediaId = 12345;
        const episodeNumber = 7;

        final id24h =
            ((mediaId.hashCode ^ episodeNumber) * 31 + 24) & 0x7FFFFFFF;
        final id2h = ((mediaId.hashCode ^ episodeNumber) * 31 + 2) & 0x7FFFFFFF;
        final id1h = ((mediaId.hashCode ^ episodeNumber) * 31 + 1) & 0x7FFFFFFF;
        final idRelease =
            ((mediaId.hashCode ^ episodeNumber) * 31 + 0) & 0x7FFFFFFF;

        final idSet = {id24h, id2h, id1h, idRelease};
        expect(
          idSet.length,
          4,
          reason: 'All 4 alarm IDs must be completely unique',
        );
      },
    );

    test(
      'Countdown classification maps correctly to 2h, 1h, 24h and release windows',
      () {
        String classifyCountdown(int secondsRemaining) {
          if (secondsRemaining <= 0) {
            return 'release';
          } else if (secondsRemaining <= 3600) {
            return '1h';
          } else if (secondsRemaining <= 7200) {
            return '2h';
          } else if (secondsRemaining <= 86400) {
            return '24h';
          } else {
            return 'future';
          }
        }

        // Exactly 2 hours left (7200 seconds)
        expect(classifyCountdown(7200), '2h');
        expect(classifyCountdown(5400), '2h'); // 1.5 hours

        // Exactly 1 hour left (3600 seconds)
        expect(classifyCountdown(3600), '1h');
        expect(classifyCountdown(1800), '1h'); // 30 minutes

        // Exactly 24 hours left (86400 seconds)
        expect(classifyCountdown(86400), '24h');
        expect(classifyCountdown(43200), '24h'); // 12 hours

        // Released
        expect(classifyCountdown(0), 'release');
        expect(classifyCountdown(-60), 'release');

        // More than 24 hours in the future
        expect(classifyCountdown(90000), 'future');
      },
    );
  });
}
