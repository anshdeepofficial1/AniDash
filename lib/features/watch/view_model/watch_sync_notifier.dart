import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:workmanager/workmanager.dart';

import 'package:ani_dash/core/models/tracker/tracker_type.dart';
import 'package:ani_dash/core/models/universal/universal_media.dart';
import 'package:ani_dash/core/repositories/local_media_repository.dart';
import 'package:ani_dash/core/repositories/watch_progress_repository.dart';
import 'package:ani_dash/core/utils/app_logger.dart';
import 'package:ani_dash/core/services/offline_sync_queue_service.dart';
import 'package:ani_dash/shared/providers/settings/sync_settings_notifier.dart';
import 'package:ani_dash/shared/providers/tracker/media_tracker_notifier.dart';
import 'package:ani_dash/shared/providers/incognito_provider.dart';

import 'package:ani_dash/core/utils/cloud_watch_progress_sync.dart';

part 'watch_sync_notifier.g.dart';

@riverpod
class WatchSyncNotifier extends _$WatchSyncNotifier {
  DateTime? _lastPositionSyncTime;

  @override
  void build() {}

  /// Process syncing to Anilist/MAL and local database mirror if criteria are met.
  Future<void> handleTrackingUpdate({
    required String mediaId,
    required int episodeNum,
    int? progressInSeconds,
    int? durationInSeconds,
  }) async {
    if (IncognitoService.isIncognito(mediaId)) return;
    final syncSettings = ref.read(syncSettingsProvider);
    final syncNotifier = ref.read(syncSettingsProvider.notifier);

    // Skip manual or prompt-based sync calls (WatchScreen handles prompt if askBeforeSync is true)
    if (syncNotifier.isManualSync || syncSettings.askBeforeSync) return;

    await updateTracking(
      mediaId: mediaId,
      episodeNum: episodeNum,
      progressInSeconds: progressInSeconds,
      durationInSeconds: durationInSeconds,
    );
  }

  /// Syncs exact watch timestamp across platforms (e.g. Android <-> Windows <-> macOS)
  Future<void> syncWatchPosition({
    required String mediaId,
    required int episodeNum,
    required int progressInSeconds,
    required int durationInSeconds,
    bool force = false,
  }) async {
    if (IncognitoService.isIncognito(mediaId)) return;
    final now = DateTime.now();
    if (!force &&
        _lastPositionSyncTime != null &&
        now.difference(_lastPositionSyncTime!).inSeconds < 10) {
      return;
    }
    _lastPositionSyncTime = now;
    await updateTracking(
      mediaId: mediaId,
      episodeNum: episodeNum,
      progressInSeconds: progressInSeconds,
      durationInSeconds: durationInSeconds,
    );
  }

  /// Forces an update to tracking without checking system automated rules
  Future<void> updateTracking({
    required String mediaId,
    required int episodeNum,
    int? progressInSeconds,
    int? durationInSeconds,
  }) async {
    if (IncognitoService.isIncognito(mediaId)) {
      AppLogger.d('Incognito active for $mediaId; skipping tracking sync.');
      return;
    }
    try {
      final syncSettings = ref.read(syncSettingsProvider);
      final syncNotifier = ref.read(syncSettingsProvider.notifier);
      final repo = ref.read(localMediaRepoProvider);
      final watchProgressRepo = ref.read(watchProgressRepositoryProvider);
      final trackerNotifier = ref.read(mediaTrackerProvider(mediaId).notifier);
      final List<Future<void>> tasks = [];

      final bindings = await repo.getBindings(mediaId);

      final activeBindings = bindings
          .where(
            (b) =>
                (b.type == TrackerType.anilist &&
                    syncNotifier.shouldSyncAnilist) ||
                (b.type == TrackerType.mal && syncNotifier.shouldSyncMal),
          )
          .toList();

      final progressEntry = watchProgressRepo.getProgress(mediaId);
      final totalEpisodes = progressEntry?.totalEpisodes;
      final isCompleted = totalEpisodes != null &&
          totalEpisodes > 0 &&
          episodeNum >= totalEpisodes;
      final trackingStatus = isCompleted ? 'COMPLETED' : 'CURRENT';

      final epProgress = progressEntry?.episodesProgress[episodeNum];
      final sec = progressInSeconds ?? epProgress?.progressInSeconds ?? 0;
      final dur = durationInSeconds ?? epProgress?.durationInSeconds ?? 1440;
      final localEntry = await trackerNotifier.getLocalEntry();
      final notesTag = CloudWatchProgressSync.formatNotes(
        existingNotes: localEntry?.notes,
        episode: episodeNum,
        seconds: sec,
        duration: dur,
      );

      if (syncSettings.syncMode == 'background') {
        final inputData = <String, dynamic>{
          'progress': episodeNum,
          'status': trackingStatus,
          'notes': notesTag,
        };
        for (final b in activeBindings) {
          if (b.type == TrackerType.anilist) {
            inputData['anilistId'] = b.remoteId;
          }
          if (b.type == TrackerType.mal) inputData['malId'] = b.remoteId;
        }

        if (inputData.containsKey('anilistId') ||
            inputData.containsKey('malId')) {
          Workmanager().registerOneOffTask(
            "sync_tracking_${mediaId}_$episodeNum",
            "sync_tracking_task",
            inputData: inputData,
            initialDelay: Duration(
              minutes: syncSettings.backgroundIntervalMinutes,
            ),
            existingWorkPolicy: ExistingWorkPolicy.replace,
          );
        }
      } else if (activeBindings.isNotEmpty) {
        tasks.add(
          trackerNotifier.syncTrackers(
            bindings: activeBindings,
            status: trackingStatus,
            progress: episodeNum,
            notes: notesTag,
          ),
        );
      }

      if (syncNotifier.shouldSyncLocal) {
        final entry = progressEntry;

        tasks.add(
          trackerNotifier.saveLocalEntry(
            UniversalMedia(
              id: mediaId,
              title: UniversalTitle(english: entry?.animeTitle ?? 'Unknown'),
              coverImage: UniversalCoverImage(large: entry?.animeCover),
              status: 'UNKNOWN',
              format: entry?.animeFormat,
              episodes: entry?.totalEpisodes,
            ),
            status: trackingStatus,
            progress: episodeNum,
            score: localEntry?.score ?? 0.0,
            repeat: localEntry?.repeat ?? 0,
            notes: notesTag,
            isPrivate: localEntry?.isPrivate ?? false,
            startedAt: DateTime.now(),
          ),
        );
      }

      if (tasks.isNotEmpty) await Future.wait(tasks);
    } catch (e) {
      AppLogger.e('Tracking update failed; queuing for offline sync: $e');
      final watchProgressRepo = ref.read(watchProgressRepositoryProvider);
      final progressEntry = watchProgressRepo.getProgress(mediaId);
      final totalEpisodes = progressEntry?.totalEpisodes;
      final isCompleted = totalEpisodes != null &&
          totalEpisodes > 0 &&
          episodeNum >= totalEpisodes;
      final fallbackStatus = isCompleted ? 'COMPLETED' : 'CURRENT';
      await OfflineSyncQueueService.enqueue(
        mediaId: mediaId,
        episodeNum: episodeNum,
        status: fallbackStatus,
      );
    }
  }
}
