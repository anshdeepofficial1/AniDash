import 'dart:convert';
import 'package:awesome_snackbar_content/awesome_snackbar_content.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';
import 'package:isar_community/isar.dart';
import 'package:ani_dash/core/utils/app_logger.dart';
import 'package:ani_dash/core/utils/app_utils.dart';
import 'package:ani_dash/data/hive/models/anime_watch_progress_model.dart';
import 'package:ani_dash/data/isar/isar_anime_watch_progress.dart';
import 'package:ani_dash/main.dart';
import 'package:ani_dash/core/repositories/interfaces/watch_progress_repository_interface.dart';
import 'package:ani_dash/shared/providers/incognito_provider.dart';

final watchProgressRepositoryProvider =
    Provider<WatchProgressRepositoryInterface>((ref) {
      return WatchProgressRepository();
    });

final watchProgressStreamProvider =
    StreamProvider.autoDispose<List<AnimeWatchProgressEntry>>((ref) {
      return ref.watch(watchProgressRepositoryProvider).watchAllProgress();
    });

final animeWatchProgressProvider = StreamProvider.autoDispose
    .family<AnimeWatchProgressEntry?, String>((ref, animeId) {
      return ref.watch(watchProgressRepositoryProvider).watchProgress(animeId);
    });

class WatchProgressRepository implements WatchProgressRepositoryInterface {
  WatchProgressRepository();

  static const _lastPlayedPrefKey = 'anime_last_played_at_map';
  bool _lastPlayedLoaded = false;
  final Map<String, DateTime> _lastPlayedMap = {};

  bool get _canUseIsar {
    try {
      return isar.isOpen;
    } catch (_) {
      return false;
    }
  }

  void _ensureLastPlayedLoaded() {
    if (_lastPlayedLoaded) return;
    _lastPlayedLoaded = true;
    try {
      final raw = sharedPrefs.getString(_lastPlayedPrefKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        for (final entry in decoded.entries) {
          final parsed = DateTime.tryParse(entry.value.toString());
          if (parsed != null) {
            _lastPlayedMap[entry.key] = parsed;
          }
        }
      }
    } catch (e) {
      AppLogger.e('Failed to load last played map from sharedPrefs: $e');
    }
  }

  DateTime? _getLastPlayed(String animeId) {
    _ensureLastPlayedLoaded();
    return _lastPlayedMap[animeId];
  }

  Future<void> _setLastPlayed(String animeId, DateTime? timestamp) async {
    _ensureLastPlayedLoaded();
    if (timestamp != null) {
      _lastPlayedMap[animeId] = timestamp;
    } else {
      _lastPlayedMap.remove(animeId);
    }
    try {
      await sharedPrefs.setString(
        _lastPlayedPrefKey,
        jsonEncode(
          _lastPlayedMap.map((k, v) => MapEntry(k, v.toIso8601String())),
        ),
      );
    } catch (e) {
      AppLogger.e('Failed to persist last played map: $e');
    }
  }

  // --- Migration ---

  @override
  Future<void> migrateFromHive() async {
    if (!_canUseIsar) return;
    try {
      final isarCount = isar.isarAnimeWatchProgress.countSync();
      if (sharedPrefs.getBool('migrated_watch_progress_isar') == true &&
          isarCount > 0) {
        return;
      }

      AppLogger.i('Starting migration of watch progress to Isar...');

      final box =
          Hive.isBoxOpen('anime_watch_progress')
              ? Hive.box<AnimeWatchProgressEntry>('anime_watch_progress')
              : await Hive.openBox<AnimeWatchProgressEntry>(
                'anime_watch_progress',
              );

      if (box.isEmpty) {
        await sharedPrefs.setBool('migrated_watch_progress_isar', true);
        return;
      }

      final entries = box.values.toList();
      final isarEntries =
          entries
              .map(
                (e) => IsarAnimeWatchProgress(
                  id: fastHash(e.animeId),
                  animeId: e.animeId,
                  animeTitle: e.animeTitle,
                  animeFormat: e.animeFormat,
                  animeCover: e.animeCover,
                  totalEpisodes: e.totalEpisodes,
                  lastUpdated: e.lastUpdated,
                  currentEpisode: e.currentEpisode,
                  status: e.status,
                  episodesProgress:
                      e.episodesProgress.values.map(_toIsarProgress).toList(),
                ),
              )
              .toList();

      await isar.writeTxn(() async {
        await isar.isarAnimeWatchProgress.putAll(isarEntries);
      });

      await sharedPrefs.setBool('migrated_watch_progress_isar', true);
      AppLogger.success(
        'Successfully migrated ${entries.length} items to Isar',
      );
    } catch (e, st) {
      AppLogger.e('Failed to migrate watch progress', e, st);
    }
  }

  @override
  Future<void> replaceAllProgress(
    Iterable<AnimeWatchProgressEntry> entries,
  ) async {
    final restored = entries.toList(growable: false);
    if (_canUseIsar) {
      try {
        final isarEntries = restored
            .map(
              (entry) => IsarAnimeWatchProgress(
                id: fastHash(entry.animeId),
                animeId: entry.animeId,
                animeTitle: entry.animeTitle,
                animeFormat: entry.animeFormat,
                animeCover: entry.animeCover,
                totalEpisodes: entry.totalEpisodes,
                lastUpdated: entry.lastUpdated,
                currentEpisode: entry.currentEpisode,
                status: entry.status,
                episodesProgress:
                    entry.episodesProgress.values.map(_toIsarProgress).toList(),
              ),
            )
            .toList(growable: false);

        await isar.writeTxn(() async {
          await isar.isarAnimeWatchProgress.clear();
          if (isarEntries.isNotEmpty) {
            await isar.isarAnimeWatchProgress.putAll(isarEntries);
          }
        });
      } catch (e, st) {
        AppLogger.e('Error replacing Isar progress: $e', e, st);
      }
    }

    final box =
        Hive.isBoxOpen('anime_watch_progress')
            ? Hive.box<AnimeWatchProgressEntry>('anime_watch_progress')
            : await Hive.openBox<AnimeWatchProgressEntry>(
              'anime_watch_progress',
            );
    await box.clear();
    await box.putAll({for (final entry in restored) entry.animeId: entry});
    await sharedPrefs.setBool('migrated_watch_progress_isar', true);
  }

  bool isAdultAnimeId(String animeId) {
    final adultIds = sharedPrefs.getStringList('adult_anime_ids') ?? [];
    return adultIds.contains(animeId);
  }

  Future<void> markAdultAnimeId(String animeId) async {
    final adultIds =
        (sharedPrefs.getStringList('adult_anime_ids') ?? []).toSet();
    if (!adultIds.contains(animeId)) {
      adultIds.add(animeId);
      await sharedPrefs.setStringList('adult_anime_ids', adultIds.toList());
    }
  }

  // --- Core CRUD ---

  @override
  Future<void> saveProgress(AnimeWatchProgressEntry entry) async {
    if (IncognitoService.isIncognito(entry.animeId)) {
      AppLogger.d(
        'Incognito active for anime: ${entry.animeTitle} (${entry.animeId}); skipping save.',
      );
      return;
    }
    if (entry.isAdult) {
      await markAdultAnimeId(entry.animeId);
    }
    if (entry.lastPlayedAt != null) {
      await _setLastPlayed(entry.animeId, entry.lastPlayedAt);
    }
    try {
      final dismissed =
          (sharedPrefs.getStringList('dismissed_continue_watching_ids') ?? [])
              .toSet();
      if (dismissed.contains(entry.animeId)) {
        dismissed.remove(entry.animeId);
        await sharedPrefs.setStringList(
          'dismissed_continue_watching_ids',
          dismissed.toList(),
        );
      }
    } catch (_) {}
    try {
      if (_canUseIsar) {
        try {
          final isarEntry = IsarAnimeWatchProgress(
            id: fastHash(entry.animeId),
            animeId: entry.animeId,
            animeTitle: entry.animeTitle,
            animeFormat: entry.animeFormat,
            animeCover: entry.animeCover,
            totalEpisodes: entry.totalEpisodes,
            lastUpdated: entry.lastUpdated,
            currentEpisode: entry.currentEpisode,
            status: entry.status,
            episodesProgress:
                entry.episodesProgress.values.map(_toIsarProgress).toList(),
          );

          await isar.writeTxn(() async {
            await isar.isarAnimeWatchProgress.put(isarEntry);
          });
        } catch (e, st) {
          AppLogger.e('Error putting watch progress to Isar: $e', e, st);
        }
      }

      // Dual-write to Hive to prevent data loss
      try {
        final box =
            Hive.isBoxOpen('anime_watch_progress')
                ? Hive.box<AnimeWatchProgressEntry>('anime_watch_progress')
                : await Hive.openBox<AnimeWatchProgressEntry>(
                  'anime_watch_progress',
                );
        await box.put(entry.animeId, entry);
      } catch (_) {}

      // Cache to SharedPreferences for background notification worker
      try {
        final currentTracked = sharedPrefs.getString(
          'cached_tracked_anime_map',
        );
        final map =
            currentTracked != null && currentTracked.isNotEmpty
                ? (jsonDecode(currentTracked) as Map<String, dynamic>)
                : <String, dynamic>{};
        map[entry.animeId] = <String, dynamic>{
          'title': entry.animeTitle,
          'currentEpisode': entry.currentEpisode,
          'totalEpisodes': entry.totalEpisodes,
          'status': entry.status,
        };
        await sharedPrefs.setString(
          'cached_tracked_anime_map',
          jsonEncode(map),
        );
      } catch (_) {}

      AppLogger.d(
        'Saved progress for anime: ${entry.animeTitle} (${entry.animeId})',
      );
    } catch (e, st) {
      AppLogger.e('Failed to save anime progress', e, st);
      showAppSnackBar(
        'Save Failed',
        'Failed to automatically save watch progress.',
        type: ContentType.failure,
      );
    }
  }

  @override
  AnimeWatchProgressEntry? getProgress(String animeId) {
    if (_canUseIsar) {
      try {
        final isarEntry =
            isar.isarAnimeWatchProgress.getSync(fastHash(animeId));
        final isAdult = isAdultAnimeId(animeId);
        final lastPlayed = _getLastPlayed(animeId);
        if (isarEntry != null) {
          return AnimeWatchProgressEntry(
            animeId: isarEntry.animeId,
            animeTitle: isarEntry.animeTitle,
            animeFormat: isarEntry.animeFormat,
            animeCover: isarEntry.animeCover,
            totalEpisodes: isarEntry.totalEpisodes,
            lastUpdated: isarEntry.lastUpdated,
            lastPlayedAt: lastPlayed,
            currentEpisode: isarEntry.currentEpisode,
            status: isarEntry.status,
            isAdult: isAdult,
            episodesProgress: {
              for (var ep in isarEntry.episodesProgress)
                ep.episodeNumber: _fromIsarProgress(ep),
            },
          );
        }
      } catch (e) {
        AppLogger.w('Isar getProgress error: $e');
      }
    }

    try {
      if (Hive.isBoxOpen('anime_watch_progress')) {
        final box = Hive.box<AnimeWatchProgressEntry>('anime_watch_progress');
        final entry = box.get(animeId);
        if (entry != null) {
          final isAdult = isAdultAnimeId(animeId);
          final lastPlayed = _getLastPlayed(animeId);
          final effectiveEntry = entry.copyWith(
            lastPlayedAt: lastPlayed ?? entry.lastPlayedAt,
            isAdult: isAdult || entry.isAdult,
          );
          return effectiveEntry;
        }
      }
    } catch (_) {}
    return null;
  }

  @override
  List<AnimeWatchProgressEntry> getAllProgress() {
    if (_canUseIsar) {
      try {
        final isarEntries = isar.isarAnimeWatchProgress.where().findAllSync();
        if (isarEntries.isNotEmpty) {
          return isarEntries.map((isarEntry) {
            final isAdult = isAdultAnimeId(isarEntry.animeId);
            final lastPlayed = _getLastPlayed(isarEntry.animeId);
            return AnimeWatchProgressEntry(
              animeId: isarEntry.animeId,
              animeTitle: isarEntry.animeTitle,
              animeFormat: isarEntry.animeFormat,
              animeCover: isarEntry.animeCover,
              totalEpisodes: isarEntry.totalEpisodes,
              lastUpdated: isarEntry.lastUpdated,
              lastPlayedAt: lastPlayed,
              currentEpisode: isarEntry.currentEpisode,
              status: isarEntry.status,
              isAdult: isAdult,
              episodesProgress: {
                for (var ep in isarEntry.episodesProgress)
                  ep.episodeNumber: _fromIsarProgress(ep),
              },
            );
          }).toList();
        }
      } catch (e, st) {
        AppLogger.e('Isar getAllProgress error: $e', e, st);
      }
    }

    try {
      final box =
          Hive.isBoxOpen('anime_watch_progress')
              ? Hive.box<AnimeWatchProgressEntry>('anime_watch_progress')
              : null;
      if (box != null && box.isNotEmpty) {
        final hiveList =
            box.values.map((e) {
              final lastPlayed = _getLastPlayed(e.animeId) ?? e.lastPlayedAt;
              return e.copyWith(lastPlayedAt: lastPlayed);
            }).toList();
        if (_canUseIsar) {
          migrateFromHive();
        }
        return hiveList;
      }
    } catch (_) {}

    return [];
  }

  // --- Update Operations ---

  @override
  Future<void> updateEpisodeProgress(
    String animeId,
    EpisodeProgress episodeProgress, {
    bool isLocalPlayback = false,
  }) async {
    var entry = getProgress(animeId);
    final now = DateTime.now();

    entry ??= AnimeWatchProgressEntry(
      animeId: animeId,
      animeTitle: '',
      animeFormat: '',
      animeCover: '',
      totalEpisodes: 0,
      lastUpdated: now,
      lastPlayedAt: now,
      currentEpisode: episodeProgress.episodeNumber,
      episodesProgress: {},
    );

    final updatedEpisodes = Map<int, EpisodeProgress>.from(
      entry.episodesProgress,
    );

    // Preserve existing thumbnail if new one is null
    final existingThumb =
        updatedEpisodes[episodeProgress.episodeNumber]?.episodeThumbnail;
    updatedEpisodes[episodeProgress.episodeNumber] = episodeProgress.copyWith(
      episodeThumbnail: episodeProgress.episodeThumbnail ?? existingThumb,
    );

    final isEpCompleted =
        episodeProgress.isCompleted ||
        ((episodeProgress.durationInSeconds ?? 0) > 0 &&
            (episodeProgress.progressInSeconds ?? 0) /
                    episodeProgress.durationInSeconds! >=
                0.90);
    final format = entry.animeFormat?.toUpperCase();
    final isOneShot =
        format == 'MOVIE' || format == 'SPECIAL' || format == 'OVA';
    final isAllWatched = isOneShot && isEpCompleted;

    final updatedEntry = entry.copyWith(
      episodesProgress: updatedEpisodes,
      lastUpdated: now,
      lastPlayedAt: now,
      currentEpisode: episodeProgress.episodeNumber,
      status: isAllWatched ? 'completed' : 'watching',
    );

    await _setLastPlayed(animeId, now);
    await saveProgress(updatedEntry);
  }

  @override
  Future<void> updateCurrentEpisode(
    String animeId,
    int currentEpisode, {
    String? animeTitle,
    String? animeCover,
    String? animeFormat,
  }) async {
    final now = DateTime.now();
    final entry = getProgress(animeId);
    if (entry != null) {
      final updated = entry.copyWith(
        currentEpisode: currentEpisode,
        lastPlayedAt: now,
        lastUpdated: now,
        status: 'watching',
      );
      await _setLastPlayed(animeId, now);
      await saveProgress(updated);
    } else if (animeTitle != null && animeTitle.isNotEmpty) {
      final newEntry = AnimeWatchProgressEntry(
        animeId: animeId,
        animeTitle: animeTitle,
        animeFormat: animeFormat,
        animeCover: animeCover ?? '',
        totalEpisodes: 0,
        lastUpdated: now,
        lastPlayedAt: now,
        status: 'watching',
        currentEpisode: currentEpisode,
        episodesProgress: {
          currentEpisode: EpisodeProgress(
            episodeNumber: currentEpisode,
            episodeTitle: 'Episode $currentEpisode',
            // The anime cover is a card fallback, not an episode thumbnail.
            // A real episode banner is persisted by WatchProgressNotifier as
            // soon as playback progress is saved.
            episodeThumbnail: null,
            progressInSeconds: 0,
            durationInSeconds: 1440,
            isCompleted: false,
            watchedAt: now,
          ),
        },
      );
      await _setLastPlayed(animeId, now);
      await saveProgress(newEntry);
    }
  }

  @override
  Future<void> markPreviousEpisodesWatched({
    required String animeId,
    required String animeTitle,
    required String animeCover,
    required String animeFormat,
    required int upToEpisodeNumber,
    int? totalEpisodes,
  }) async {
    var entry = getProgress(animeId);
    entry ??= AnimeWatchProgressEntry(
      animeId: animeId,
      animeTitle: animeTitle,
      animeFormat: animeFormat,
      animeCover: animeCover,
      totalEpisodes: totalEpisodes ?? 0,
      lastUpdated: DateTime.fromMillisecondsSinceEpoch(0),
      lastPlayedAt: null,
      currentEpisode: upToEpisodeNumber,
      episodesProgress: {},
    );

    final updatedEpisodes = Map<int, EpisodeProgress>.from(
      entry.episodesProgress,
    );

    for (int i = 1; i <= upToEpisodeNumber; i++) {
      final existing = updatedEpisodes[i];
      updatedEpisodes[i] = EpisodeProgress(
        episodeNumber: i,
        episodeTitle: existing?.episodeTitle ?? 'Episode $i',
        episodeThumbnail: existing?.episodeThumbnail,
        isCompleted: true,
        watchedAt:
            existing?.watchedAt ?? DateTime.fromMillisecondsSinceEpoch(0),
      );
    }

    final effectiveTotal =
        (totalEpisodes != null && totalEpisodes > 0)
            ? totalEpisodes
            : entry.totalEpisodes;
    final isAllWatched =
        effectiveTotal > 0 && upToEpisodeNumber >= effectiveTotal;

    final updatedEntry = entry.copyWith(
      episodesProgress: updatedEpisodes,
      totalEpisodes: effectiveTotal > 0 ? effectiveTotal : entry.totalEpisodes,
      lastPlayedAt: entry.lastPlayedAt,
      currentEpisode: upToEpisodeNumber,
      status: isAllWatched ? 'completed' : entry.status,
      animeTitle: animeTitle.isNotEmpty ? animeTitle : entry.animeTitle,
      animeCover: animeCover.isNotEmpty ? animeCover : entry.animeCover,
    );

    await saveProgress(updatedEntry);
  }

  // --- Deletion ---

  @override
  Future<void> deleteProgress(String animeId) async {
    await _setLastPlayed(animeId, null);
    if (_canUseIsar) {
      try {
        await isar.writeTxn(() async {
          await isar.isarAnimeWatchProgress.delete(fastHash(animeId));
        });
      } catch (e, st) {
        AppLogger.e('Error deleting watch progress from Isar: $e', e, st);
      }
    }
    try {
      if (Hive.isBoxOpen('anime_watch_progress')) {
        final box = Hive.box<AnimeWatchProgressEntry>('anime_watch_progress');
        await box.delete(animeId);
      }
    } catch (_) {}
    try {
      final currentTracked = sharedPrefs.getString('cached_tracked_anime_map');
      if (currentTracked != null && currentTracked.isNotEmpty) {
        final map = jsonDecode(currentTracked) as Map<String, dynamic>;
        map.remove(animeId);
        await sharedPrefs.setString(
          'cached_tracked_anime_map',
          jsonEncode(map),
        );
      }
    } catch (_) {}
    AppLogger.d('Deleted progress for anime: $animeId');
  }

  @override
  Future<void> deleteEpisodeProgress(String animeId, int episodeNumber) async {
    final entry = getProgress(animeId);
    if (entry == null) return;

    final updatedEpisodes = Map<int, EpisodeProgress>.from(
      entry.episodesProgress,
    );
    updatedEpisodes.remove(episodeNumber);

    if (updatedEpisodes.isEmpty) {
      await deleteProgress(animeId);
      return;
    }

    // Safely find highest episode number
    final newCurrentEpisode = updatedEpisodes.keys.reduce(
      (a, b) => a > b ? a : b,
    );
    final updatedEntry = entry.copyWith(
      episodesProgress: updatedEpisodes,
      lastPlayedAt: entry.lastPlayedAt,
      currentEpisode: newCurrentEpisode,
    );
    await saveProgress(updatedEntry);
    AppLogger.d('Deleted episode $episodeNumber progress for anime: $animeId');
  }

  @override
  Future<void> deleteMultipleProgress(List<String> animeIds) async {
    _ensureLastPlayedLoaded();
    for (final id in animeIds) {
      _lastPlayedMap.remove(id);
    }
    try {
      await sharedPrefs.setString(
        _lastPlayedPrefKey,
        jsonEncode(
          _lastPlayedMap.map((k, v) => MapEntry(k, v.toIso8601String())),
        ),
      );
    } catch (_) {}
    if (_canUseIsar) {
      try {
        await isar.writeTxn(() async {
          await isar.isarAnimeWatchProgress.deleteAll(
            animeIds.map(fastHash).toList(),
          );
        });
      } catch (e, st) {
        AppLogger.e('Error bulk deleting from Isar: $e', e, st);
      }
    }
    try {
      if (Hive.isBoxOpen('anime_watch_progress')) {
        final box = Hive.box<AnimeWatchProgressEntry>('anime_watch_progress');
        await box.deleteAll(animeIds);
      }
    } catch (_) {}
    AppLogger.d('Deleted progress for ${animeIds.length} animes');
  }

  @override
  EpisodeProgress? getEpisodeProgress(String animeId, int episodeNumber) {
    return getProgress(animeId)?.episodesProgress[episodeNumber];
  }

  // --- Streams ---

  @override
  Stream<List<AnimeWatchProgressEntry>> watchAllProgress() async* {
    yield getAllProgress();
    if (_canUseIsar) {
      try {
        await for (final _ in isar.isarAnimeWatchProgress.where().watch()) {
          yield getAllProgress();
        }
      } catch (e) {
        AppLogger.w('watchAllProgress stream error: $e');
      }
    }
  }

  @override
  Stream<AnimeWatchProgressEntry?> watchProgress(String animeId) async* {
    yield getProgress(animeId);
    if (_canUseIsar) {
      try {
        await for (final _
            in isar.isarAnimeWatchProgress
                .filter()
                .idEqualTo(fastHash(animeId))
                .watch()) {
          yield getProgress(animeId);
        }
      } catch (e) {
        AppLogger.w('watchProgress stream error: $e');
      }
    }
  }

  // --- Private Helpers ---

  IsarEpisodeProgress _toIsarProgress(EpisodeProgress ep) {
    return IsarEpisodeProgress(
      episodeNumber: ep.episodeNumber,
      episodeTitle: ep.episodeTitle,
      episodeThumbnail: ep.episodeThumbnail,
      progressInSeconds: ep.progressInSeconds,
      durationInSeconds: ep.durationInSeconds,
      isCompleted: ep.isCompleted,
      watchedAt: ep.watchedAt,
    );
  }

  EpisodeProgress _fromIsarProgress(IsarEpisodeProgress ep) {
    return EpisodeProgress(
      episodeNumber: ep.episodeNumber,
      episodeTitle: ep.episodeTitle,
      episodeThumbnail: ep.episodeThumbnail,
      progressInSeconds: ep.progressInSeconds,
      durationInSeconds: ep.durationInSeconds,
      isCompleted: ep.isCompleted,
      watchedAt: ep.watchedAt,
    );
  }
}
