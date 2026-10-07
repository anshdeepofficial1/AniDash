import 'dart:convert';
import 'package:ani_dash/core/models/aniskip/aniskip_result.dart';
import 'package:ani_dash/core/network/http_client.dart';
import 'package:ani_dash/core/utils/app_logger.dart';

class AniSkipService {
  static const String _baseUrl = 'https://api.aniskip.com/v2';

  Future<List<AniSkipResultItem>> getSkipTimes(
    int malId,
    int episodeNumber,
    int episodeLength,
  ) async {
    try {
      // Always include the real episode length. Results requested with zero can
      // be aligned to a different cut and may span most of the episode.
      final uri = Uri.parse(
        '$_baseUrl/skip-times/$malId/$episodeNumber?types[]=op&types[]=ed&types[]=mixed-op&types[]=mixed-ed&types[]=recap&episodeLength=$episodeLength',
      );

      final response = await UniversalHttpClient.instance.get(
        uri,
        cacheConfig: CacheConfig.veryLong,
      );

      AppLogger.d('AniSkip API response: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final result = AniSkipResponse.fromJson(data);
        if (result.found && result.results.isNotEmpty) {
          return _validIntervals(result.results, episodeLength);
        }
      }

      // Older AniSkip entries may only respond without an episode length. Keep
      // that as a fallback, but strictly validate the returned timestamps.
      if (episodeLength > 0) {
        final fallbackUri = Uri.parse(
          '$_baseUrl/skip-times/$malId/$episodeNumber?types[]=op&types[]=ed&types[]=mixed-op&types[]=mixed-ed&types[]=recap&episodeLength=0',
        );
        final fallbackRes = await UniversalHttpClient.instance.get(
          fallbackUri,
          cacheConfig: CacheConfig.veryLong,
        );
        if (fallbackRes.statusCode == 200) {
          final data = jsonDecode(fallbackRes.body);
          final result = AniSkipResponse.fromJson(data);
          if (result.found) {
            return _validIntervals(result.results, episodeLength);
          }
        }
      }
    } catch (e) {
      AppLogger.e('Failed to fetch AniSkip data: $e');
    }
    return [];
  }

  List<AniSkipResultItem> _validIntervals(
    List<AniSkipResultItem> results,
    int episodeLength,
  ) {
    if (episodeLength <= 0) {
      // Preliminary lookup used before the player opens.
      // Accept both conservative opening and ending intervals.
      return results
          .where((item) {
            final interval = item.interval;
            if (interval == null) return false;
            final length = interval.endTime - interval.startTime;
            if (length < 15 || length > 180) return false;

            final isOpening =
                item.skipType == SkipType.op ||
                (item.skipType == SkipType.mixed && interval.startTime <= 300);
            final isEnding =
                item.skipType == SkipType.ed ||
                (item.skipType == SkipType.mixed && interval.startTime >= 480);

            if (isOpening) {
              return interval.startTime >= 0 &&
                  interval.startTime <= 300 &&
                  interval.endTime > interval.startTime;
            }
            if (isEnding) {
              return interval.startTime >= 480 &&
                  interval.endTime > interval.startTime;
            }
            if (item.skipType == SkipType.recap) {
              return interval.startTime >= 0 &&
                  interval.startTime <= 360 &&
                  interval.endTime > interval.startTime;
            }
            return false;
          })
          .toList(growable: false);
    }
    return results
        .where((item) {
          final interval = item.interval;
          if (interval == null) return false;
          final start = interval.startTime;
          final end = interval.endTime;
          final length = end - start;
          if (start < 0 || end <= start || end > episodeLength + 3) {
            return false;
          }
          if (length < 15 || length > 180) return false;

          switch (item.skipType) {
            case SkipType.op:
              // An anime opening MUST start within the first 5 minutes (<= 300 seconds).
              // It can NEVER start at 10-15 minutes into an episode!
              return start >= 0 && start <= 300;
            case SkipType.ed:
              // An anime ending must start in the second half (>= 60%) and after 480 seconds (8 mins).
              return start >= 480 && start >= episodeLength * 0.60;
            case SkipType.mixed:
              return (start >= 0 && start <= 300) ||
                  (start >= 480 && start >= episodeLength * 0.60);
            case SkipType.recap:
              return start >= 0 && start <= 360;
            default:
              return false;
          }
        })
        .toList(growable: false);
  }
}

final aniSkipService = AniSkipService();
