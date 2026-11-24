import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:ani_dash/core/services/anilist/anilist_service.dart';
import 'package:ani_dash/core/services/myanimelist/mal_service.dart';
import 'package:ani_dash/core/utils/app_logger.dart';
import 'package:ani_dash/core/utils/cloud_watch_progress_sync.dart';

class SyncTrackingTask {
  static Future<bool> performSync(Map<String, dynamic>? inputData) async {
    if (inputData == null) return false;

    try {
      final progress = inputData['progress'] as int?;
      if (progress == null) return false;

      final anilistId = inputData['anilistId'] as String?;
      final malId = inputData['malId'] as String?;

      bool success = true;
      const secureStorage = FlutterSecureStorage();

      if (anilistId != null) {
        final anilistToken = await secureStorage.read(key: 'anilist-token');
        final expectedOwner = inputData['anilistOwner'] as String?;
        final position = CloudWatchProgressSync.parseNotes(inputData['notes'] as String?);
        if (anilistToken == null || anilistToken.isEmpty) {
          success = false;
        } else if (expectedOwner != null && position != null) {
          // Confirm the current token belongs to the account that scheduled this task.
          final service = AnilistService(
            getAuthContext: () => (userId: expectedOwner, accessToken: anilistToken),
            getAdultParam: () => false,
          );
          try {
            final profile = await service.getUserProfile(anilistToken);
            if (profile['id']?.toString() != expectedOwner) {
              // A signed-out or different account must never receive the old checkpoint.
              return true;
            }
            final id = int.tryParse(anilistId);
            if (id == null) return false;
            final remote = await service.getAnimeEntry(id);
            if (remote == null) return false;
            final baseline = CloudWatchProgressSync.parseNotes(inputData['baseNotes'] as String?);
            final current = CloudWatchProgressSync.parseNotes(remote.notes);
            if (baseline != current || remote.progress != inputData['baseProgress']) {
              // Another device changed progress after scheduling. Never overwrite it.
              AppLogger.i('Skipped stale AniList background checkpoint');
            } else {
              final notes = CloudWatchProgressSync.formatNotes(
                existingNotes: remote.notes,
                episode: position.episode,
                seconds: position.seconds,
                duration: position.duration,
              );
              final saved = await service.updateUserAnimeList(
                mediaId: id,
                status: remote.status == 'COMPLETED' ? 'COMPLETED' : (inputData['status'] as String? ?? 'CURRENT'),
                progress: progress > remote.progress ? progress : remote.progress,
                notes: notes,
              );
              if (saved == null) success = false;
            }
          } catch (e) {
            AppLogger.e('Background AniList checkpoint failed', e);
            success = false;
          }
        } // Older jobs lack account ownership and cannot safely write progress.
      }

      if (malId != null) {
        final malToken = await secureStorage.read(key: 'mal-token');
        if (malToken != null && malToken.isNotEmpty) {
          final service = MyAnimeListService(
            getAccessToken: () => malToken,
            getShowAdult: () => false,
            onTokenRefresh: () async => false,
          );

          try {
            final id = int.tryParse(malId);
            if (id != null) {
              await service.updateUserAnimeList(
                mediaId: id,
                status: 'watching',
                progress: progress,
              );
              AppLogger.i('Background sync to MAL succeeded for id $id');
            }
          } catch (e) {
            AppLogger.e('Background sync to MAL failed', e);
            success = false;
          }
        }
      }

      return success;
    } catch (e) {
      AppLogger.e('SyncTrackingTask crashed', e);
      return false;
    }
  }
}
