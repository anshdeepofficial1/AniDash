import 'dart:convert';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:screenshot/screenshot.dart';

import 'package:ani_dash/core/repositories/interfaces/watch_progress_repository_interface.dart';
import 'package:ani_dash/core/repositories/watch_progress_repository.dart';
import 'package:ani_dash/core/utils/app_logger.dart';
import 'package:ani_dash/data/hive/models/anime_watch_progress_model.dart';

part 'watch_progress_notifier.g.dart';

@riverpod
class WatchProgressNotifier extends _$WatchProgressNotifier {
  WatchProgressRepositoryInterface? _repo;
  ScreenshotController? _screenshotController;
  int _lastSavedPos = -1;

  @override
  void build() {
    _repo = ref.read(watchProgressRepositoryProvider);
  }

  void setScreenshotController(ScreenshotController controller) {
    _screenshotController = controller;
  }

  Future<String?> captureScreenshot() async {
    if (_screenshotController == null) return null;
    try {
      final bytes = await _screenshotController!.capture(pixelRatio: 0.5);
      return bytes != null ? base64Encode(bytes) : null;
    } catch (_) {
      return null;
    }
  }

  /// Reset the internal last saved position when changing episodes
  void resetLastSavedPosition() {
    _lastSavedPos = -1;
  }

  Future<String?> saveProgress({
    required String mediaId,
    required String animeName,
    required String? animeFormat,
    required String animeCover,
    required int totalEps,
    required int epNum,
    required String? epTitle,
    String? epThumb,
    required int pos,
    required int dur,
    bool takeScreenshot = false,
    bool isAdult = false,
    bool force = false,
  }) async {
    if (_repo == null ||
        dur <= 0 ||
        pos <= 0 ||
        (!force && pos == _lastSavedPos)) {
      return epThumb;
    }

    String? currentThumb = epThumb;

    try {
      // Prefer the provider's episode banner. Capture a frame only when the
      // episode list did not supply artwork, rather than replacing official
      // episode thumbnails with arbitrary playback frames.
      if (takeScreenshot && (currentThumb == null || currentThumb.isEmpty)) {
        final thumb = await captureScreenshot();
        if (thumb != null) currentThumb = thumb;
      }

      var entry =
          _repo!.getProgress(mediaId) ??
          AnimeWatchProgressEntry(
            animeId: mediaId,
            animeTitle: animeName,
            animeFormat: animeFormat,
            animeCover: animeCover,
            totalEpisodes: totalEps,
            isAdult: isAdult,
          );
      if (totalEps > 0 && entry.totalEpisodes == 0) {
        entry = entry.copyWith(totalEpisodes: totalEps);
      }
      if (isAdult && !entry.isAdult) {
        entry = entry.copyWith(isAdult: true);
      }

      final previousDuration =
          entry.episodesProgress[epNum]?.durationInSeconds ?? 0;
      // Never replace a known full duration with a transient HLS segment
      // duration while the manifest is reconnecting.
      final stableDuration = dur > previousDuration ? dur : previousDuration;
      final isCompleted = isPlaybackEffectivelyComplete(
        progressInSeconds: pos,
        durationInSeconds: stableDuration,
      );
      final normalizedFormat = animeFormat?.toUpperCase();
      final isOneShot =
          normalizedFormat == 'SPECIAL' ||
          normalizedFormat == 'MOVIE' ||
          normalizedFormat == 'OVA';
      // Provider episode totals can be partial (especially for ongoing shows).
      // Never hide an episodic series from Continue Watching merely because
      // the current episode equals a temporarily reported total.
      final isAnimeFinished = isOneShot && isCompleted;
      if (isAnimeFinished) {
        entry = entry.copyWith(status: 'completed');
      } else {
        entry = entry.copyWith(status: 'watching');
      }

      final now = DateTime.now();
      final progress = EpisodeProgress(
        episodeNumber: epNum,
        episodeTitle: epTitle ?? 'Episode $epNum',
        episodeThumbnail: currentThumb,
        progressInSeconds: pos,
        durationInSeconds: stableDuration,
        isCompleted: isCompleted,
        watchedAt: now,
      );

      entry = entry.copyWith(lastPlayedAt: now, lastUpdated: now);

      await _repo!.saveProgress(entry);
      await _repo!.updateEpisodeProgress(
        mediaId,
        progress,
        isLocalPlayback: true,
      );

      _lastSavedPos = pos;
    } catch (e) {
      AppLogger.e('WatchProgressNotifier: Save failed', e);
    }

    return currentThumb;
  }
}
