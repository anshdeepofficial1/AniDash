import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ani_dash/shared/providers/anime_source_provider.dart';

/// Live health of each built-in anime source.
///
/// Health is intentionally advisory: one slow/empty request must not disable a
/// source that can still resolve an episode a moment later. Two independent
/// catalogue probes are used and only two hard failures mark a source offline.
final animeSourceHealthProvider = FutureProvider<Map<String, dynamic>>((
  ref,
) async {
  final registry = ref.read(animeSourceRegistryProvider);
  final statusMap = <String, dynamic>{};

  await Future.wait(
    registry.keys.map((key) async {
      final provider = registry.get(key);
      if (provider == null) {
        statusMap[key] = {'status': 'offline'};
        return;
      }
      final timer = Stopwatch()..start();
      var successes = 0;
      var hardFailures = 0;
      var emptyResponses = 0;

      // Different queries avoid treating a provider-specific indexing miss as
      // an outage. They run concurrently so the status screen stays quick.
      await Future.wait(
        const ['one piece', 'naruto'].map((query) async {
          try {
            final result = await provider
                .getSearch(query, null, 1)
                .timeout(const Duration(seconds: 12));
            if (result.results.isNotEmpty) {
              successes++;
            } else {
              emptyResponses++;
            }
          } catch (_) {
            hardFailures++;
          }
        }),
      );
      timer.stop();

      final status =
          successes > 0
              ? (hardFailures > 0 ||
                      emptyResponses > 0 ||
                      timer.elapsedMilliseconds > 7000
                  ? 'degraded'
                  : 'online')
              : hardFailures == 2
              ? 'offline'
              : 'degraded';
      statusMap[key] = {
        'status': status,
        'latencyMs': timer.elapsedMilliseconds,
        'successfulProbes': successes,
        'failedProbes': hardFailures,
      };
    }),
  );

  return statusMap;
});
