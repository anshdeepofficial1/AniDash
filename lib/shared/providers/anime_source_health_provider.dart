import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ani_dash/shared/providers/anime_source_provider.dart';

/// Live health of each built-in anime source.
///
/// A source is online only when a real catalogue request returns usable
/// results, so a reachable landing page cannot mask a broken source API.
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
      try {
        final timer = Stopwatch()..start();
        final result = await provider
            .getSearch('one piece', null, 1)
            .timeout(const Duration(seconds: 9));
        timer.stop();
        final working = result.results.isNotEmpty;
        statusMap[key] = {
          'status':
              !working
                  ? 'offline'
                  : timer.elapsedMilliseconds > 4000
                  ? 'degraded'
                  : 'online',
          'latencyMs': timer.elapsedMilliseconds,
        };
      } catch (_) {
        statusMap[key] = {'status': 'offline'};
      }
    }),
  );

  return statusMap;
});
