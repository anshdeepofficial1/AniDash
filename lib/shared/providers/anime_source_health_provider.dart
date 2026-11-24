import 'dart:async';

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
  final refreshTimer = Timer(const Duration(minutes: 5), ref.invalidateSelf);
  ref.onDispose(refreshTimer.cancel);
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
              : hardFailures + emptyResponses == 2
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

/// Keeps a persisted built-in selection usable when its upstream disappears.
/// Installed extensions are represented by a null native key and are never
/// changed by this coordinator.
final animeSourceAvailabilityCoordinatorProvider = Provider<void>((ref) {
  ref.listen<AsyncValue<Map<String, dynamic>>>(animeSourceHealthProvider, (
    previous,
    next,
  ) {
    final statusMap = next.asData?.value;
    final current = ref.read(selectedProviderKeyProvider)?.trim().toLowerCase();
    if (statusMap == null || current == null || current.isEmpty) return;
    if (statusMap[current]?['status'] != 'offline') return;

    String? replacement;
    for (final desiredStatus in const ['online', 'degraded']) {
      for (final key in const ['hianime', 'anikoto', 'justanime']) {
        if (key != current && statusMap[key]?['status'] == desiredStatus) {
          replacement = key;
          break;
        }
      }
      if (replacement != null) break;
    }
    if (replacement != null) {
      ref.read(selectedProviderKeyProvider.notifier).select(replacement);
    }
  }, fireImmediately: true);
});
