import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:ani_dash/core/repositories/watch_progress_repository.dart';
import 'package:ani_dash/data/hive/models/anime_watch_progress_model.dart';
import 'package:ani_dash/shared/providers/continue_watching_dismissed_provider.dart';

part 'watch_history_notifier.g.dart';

class WatchHistoryState {
  final List<AnimeWatchProgressEntry> history;
  final String searchQuery;

  WatchHistoryState({this.history = const [], this.searchQuery = ''});

  List<AnimeWatchProgressEntry> get filteredHistory {
    return history
        .where(
          (e) => e.animeTitle.toLowerCase().contains(searchQuery.toLowerCase()),
        )
        .toList();
  }

  WatchHistoryState copyWith({
    List<AnimeWatchProgressEntry>? history,
    String? searchQuery,
  }) {
    return WatchHistoryState(
      history: history ?? this.history,
      searchQuery: searchQuery ?? this.searchQuery,
    );
  }
}

@riverpod
class WatchHistoryNotifier extends _$WatchHistoryNotifier {
  @override
  WatchHistoryState build() {
    ref.listen(watchProgressStreamProvider, (prev, next) {
      if (next.hasValue) {
        _updateHistory(next.value!);
      }
    });

    ref.listen(continueWatchingDismissedProvider, (prev, next) {
      try {
        final history =
            ref.read(watchProgressRepositoryProvider).getAllProgress();
        state = state.copyWith(history: _processHistory(history));
      } catch (_) {}
    });

    final history = () {
      try {
        return ref.read(watchProgressRepositoryProvider).getAllProgress();
      } catch (_) {
        return <AnimeWatchProgressEntry>[];
      }
    }();
    return WatchHistoryState(history: _processHistory(history));
  }

  void _updateHistory(List<AnimeWatchProgressEntry> data) {
    state = state.copyWith(history: _processHistory(data));
  }

  List<AnimeWatchProgressEntry> _processHistory(
    List<AnimeWatchProgressEntry> list,
  ) {
    final dismissedIds = ref.read(continueWatchingDismissedProvider);
    final copy = List<AnimeWatchProgressEntry>.from(list);
    copy.removeWhere((e) {
      if (!e.hasAnyWatchProgress) return true;
      if (dismissedIds.contains(e.animeId)) return true;
      if (e.isCompletedOrFinished) return true;
      return false;
    });
    final Map<String, AnimeWatchProgressEntry> uniqueMap = {};
    for (final e in copy) {
      if (!uniqueMap.containsKey(e.animeId) ||
          e.effectiveLastPlayedTime.isAfter(uniqueMap[e.animeId]!.effectiveLastPlayedTime)) {
        uniqueMap[e.animeId] = e;
      }
    }
    final result = uniqueMap.values.toList()
      ..sort(AnimeWatchProgressEntry.compareByRecency);
    return result;
  }

  void setSearchQuery(String query) {
    state = state.copyWith(searchQuery: query);
  }

  Future<void> deleteProgress(String animeId) async {
    ref.read(continueWatchingDismissedProvider.notifier).stageDismiss(animeId);
    await ref.read(watchProgressRepositoryProvider).deleteProgress(animeId);
  }
}

// Detail State & Notifier
class AnimeHistoryDetailState {
  final AnimeWatchProgressEntry? entry;
  final String searchQuery;

  AnimeHistoryDetailState({this.entry, this.searchQuery = ''});

  List<EpisodeProgress> get filteredEpisodes {
    if (entry == null) return [];
    final episodes = entry!.episodesProgress.values.toList()
      ..sort(
        (a, b) =>
            (b.watchedAt ?? DateTime(0)).compareTo(a.watchedAt ?? DateTime(0)),
      );

    return episodes
        .where(
          (e) =>
              e.episodeNumber.toString().contains(searchQuery) ||
              (e.episodeTitle.toLowerCase().contains(
                searchQuery.toLowerCase(),
              )),
        )
        .toList();
  }

  AnimeHistoryDetailState copyWith({
    AnimeWatchProgressEntry? entry,
    String? searchQuery,
    bool nullEntry = false,
  }) {
    return AnimeHistoryDetailState(
      entry: nullEntry ? null : (entry ?? this.entry),
      searchQuery: searchQuery ?? this.searchQuery,
    );
  }
}

@riverpod
class AnimeHistoryDetailNotifier extends _$AnimeHistoryDetailNotifier {
  @override
  AnimeHistoryDetailState build(String animeId) {
    ref.listen(watchProgressStreamProvider, (prev, next) {
      if (next.hasValue) {
        final entry = next.value!
            .where((e) => e.animeId == animeId)
            .firstOrNull;
        state = state.copyWith(entry: entry, nullEntry: entry == null);
      }
    });

    final entry = () {
      try {
        return ref.read(watchProgressRepositoryProvider).getProgress(animeId);
      } catch (_) {
        return null;
      }
    }();
    return AnimeHistoryDetailState(entry: entry);
  }

  void setSearchQuery(String query) {
    state = state.copyWith(searchQuery: query);
  }

  Future<void> deleteEpisodeProgress(int episodeNumber) async {
    await ref
        .read(watchProgressRepositoryProvider)
        .deleteEpisodeProgress(animeId, episodeNumber);
  }
}
