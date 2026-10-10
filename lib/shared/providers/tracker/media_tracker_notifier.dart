import 'package:collection/collection.dart';
import 'package:ani_dash/core/models/tracker/tracker_binding.dart';
import 'package:ani_dash/core/models/tracker/tracker_type.dart';
import 'package:ani_dash/core/models/universal/universal_media.dart';
import 'package:ani_dash/core/models/universal/universal_media_list_entry.dart';
import 'package:ani_dash/core/repositories/interfaces/local_media_repository_interface.dart';
import 'package:ani_dash/core/repositories/local_media_repository.dart';
import 'package:ani_dash/core/repositories/watch_progress_repository.dart';
import 'package:ani_dash/core/services/auth_provider_enum.dart';
import 'package:ani_dash/core/utils/app_logger.dart';
import 'package:ani_dash/data/hive/models/anime_watch_progress_model.dart';
import 'package:ani_dash/shared/auth/providers/auth_notifier.dart';
import 'package:ani_dash/shared/providers/anilist_service_provider.dart';
import 'package:ani_dash/shared/providers/mal_service_provider.dart';
import 'package:ani_dash/shared/providers/tracker/tracker_service.dart';
import 'package:ani_dash/core/utils/cloud_watch_progress_sync.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'media_tracker_notifier.g.dart';

class TrackerState {
  final bool isLoading;
  final List<TrackerBinding> bindings;
  final Map<TrackerType, UniversalMediaListEntry> entries;
  final Map<TrackerType, List<String>> supportedStatuses;
  final bool remoteLoaded;

  static const Map<TrackerType, List<String>> _defaultStatuses = {
    TrackerType.anilist: [
      'CURRENT',
      'COMPLETED',
      'PAUSED',
      'DROPPED',
      'PLANNING',
      'REPEATING',
    ],
    TrackerType.mal: ['CURRENT', 'COMPLETED', 'PAUSED', 'DROPPED', 'PLANNING'],
  };

  const TrackerState({
    this.isLoading = false,
    this.bindings = const [],
    this.entries = const {},
    this.supportedStatuses = _defaultStatuses,
    this.remoteLoaded = false,
  });

  TrackerState copyWith({
    bool? isLoading,
    List<TrackerBinding>? bindings,
    Map<TrackerType, UniversalMediaListEntry>? entries,
    Map<TrackerType, List<String>>? supportedStatuses,
    bool? remoteLoaded,
  }) {
    return TrackerState(
      isLoading: isLoading ?? this.isLoading,
      bindings: bindings ?? this.bindings,
      entries: entries ?? this.entries,
      supportedStatuses: supportedStatuses ?? this.supportedStatuses,
      remoteLoaded: remoteLoaded ?? this.remoteLoaded,
    );
  }
}

@Riverpod(keepAlive: true)
class MediaTracker extends _$MediaTracker {
  @override
  TrackerState build(String mediaId) {
    _loadLocalBindings();
    return const TrackerState();
  }

  Future<void> _loadLocalBindings() async {
    var bindings = await _repo.getBindings(mediaId);
    if (bindings.isEmpty) {
      final anilistId = int.tryParse(mediaId);
      if (anilistId != null) {
        final defaultBinding = TrackerBinding(
          type: TrackerType.anilist,
          remoteId: mediaId,
        );
        bindings = [defaultBinding];
        await _repo.addBinding(mediaId, TrackerType.anilist, mediaId);
      }
    }
    state = state.copyWith(bindings: bindings);
    await fetchRemoteEntries();
  }

  Future<void> fetchRemoteEntries() async {
    if (state.remoteLoaded) return;

    final currentState = state;
    if (currentState.bindings.isEmpty) {
      state = currentState.copyWith(remoteLoaded: true);
      return;
    }

    state = currentState.copyWith(isLoading: true);

    try {
      final entries = <TrackerType, UniversalMediaListEntry>{};

      await Future.wait(
        currentState.bindings.map((binding) async {
          final remoteIdStr = binding.remoteId;
          if (remoteIdStr == null) return;

          final id = int.tryParse(remoteIdStr);
          if (id == null) return;

          try {
            UniversalMediaListEntry? entry;
            if (binding.type == TrackerType.anilist) {
              final anilist = ref.read(anilistServiceProvider);
              entry = await anilist.getAnimeEntry(id);
            } else if (binding.type == TrackerType.mal) {
              final mal = ref.read(malServiceProvider);
              entry = await mal.getAnimeEntry(id);
            }
            if (entry != null) entries[binding.type] = entry;
          } catch (e) {
            AppLogger.e(
              'Failed to fetch ${binding.type.name} entry for ID ${binding.remoteId}',
              e,
            );
          }
        }),
      );

      state = state.copyWith(
        isLoading: false,
        entries: entries,
        remoteLoaded: true,
      );

      await _syncProgressFromActiveTracker(entries);
    } catch (e) {
      state = state.copyWith(isLoading: false, remoteLoaded: true);
    }
  }

  Future<void> addTrackerBinding(TrackerType type, String remoteId) async {
    final currentState = state;
    state = currentState.copyWith(isLoading: true);

    try {
      final newBinding = TrackerBinding(type: type, remoteId: remoteId);

      await _repo.addBinding(mediaId, type, remoteId);

      UniversalMediaListEntry? newEntry;
      final id = int.tryParse(remoteId);
      if (id != null) {
        try {
          if (type == TrackerType.anilist) {
            final anilist = ref.read(anilistServiceProvider);
            newEntry = await anilist.getAnimeEntry(id);
          } else if (type == TrackerType.mal) {
            final mal = ref.read(malServiceProvider);
            newEntry = await mal.getAnimeEntry(id);
          }
        } catch (e) {
          AppLogger.e(
            'Failed to fetch or create new ${type.name} entry for ID $remoteId',
            e,
          );
        }
      }

      final updatedBindings = List<TrackerBinding>.from(currentState.bindings)
        ..removeWhere((b) => b.type == type)
        ..add(newBinding);

      final updatedEntries = Map<TrackerType, UniversalMediaListEntry>.from(
        currentState.entries,
      );
      if (newEntry != null) {
        updatedEntries[type] = newEntry;
      }

      state = currentState.copyWith(
        isLoading: false,
        bindings: updatedBindings,
        entries: updatedEntries,
      );

      await _syncProgressFromActiveTracker(updatedEntries);
    } catch (e) {
      state = currentState.copyWith(isLoading: false);
      throw Exception('Failed to bind tracker: $e');
    }
  }

  ///Sync specific trackers directly
  Future<void> syncTrackers({
    required List<TrackerBinding> bindings,
    String? status,
    int? progress,
    double? score,
    int? repeat,
    String? notes,
    bool? isPrivate,
  }) async {
    final Map<TrackerType, TrackerService> services = {
      TrackerType.anilist: ref.read(anilistServiceProvider),
      TrackerType.mal: ref.read(malServiceProvider),
    };

    final List<Future<void>> tasks = [];

    for (final binding in bindings) {
      if (binding.remoteId == null) continue;
      final service = services[binding.type];

      if (service == null) continue;

      tasks.add(
        service
            .updateEntry(
              remoteId: binding.remoteId!,
              status: status,
              progress: progress,
              score: score,
              repeat: repeat,
              notes: notes,
              isPrivate: isPrivate,
            )
            .then((value) {
              final current = state.entries[binding.type];
              if (current != null) {
                state.entries[binding.type] = current.copyWith(
                  status: status,
                  progress: progress,
                  score: score,
                  repeat: repeat,
                  notes: notes,
                  isPrivate: isPrivate,
                );
              }
            })
            .catchError((e) {
              AppLogger.e(
                'Failed to update tracker entry for ${binding.type}',
                e,
              );
              return;
            }),
      );
    }
  }

  /// Extracted sync for the UI
  Future<void> syncForTracker(
    TrackerType type, {
    String? status,
    int? progress,
    double? score,
  }) async {
    final currentState = state;
    state = currentState.copyWith(isLoading: true);

    try {
      final binding = currentState.bindings.firstWhereOrNull(
        (b) => b.type == type,
      );

      if (binding == null || binding.remoteId == null) {
        state = currentState.copyWith(isLoading: false);
        return;
      }

      await syncTrackers(
        bindings: [binding],
        status: status,
        progress: progress,
        score: score,
      );

      final updatedEntries = Map<TrackerType, UniversalMediaListEntry>.from(
        currentState.entries,
      );

      if (updatedEntries.containsKey(type)) {
        updatedEntries[type] = updatedEntries[type]!.copyWith(
          status: status,
          progress: progress,
          score: score,
        );
      } else {
        final id = int.tryParse(binding.remoteId!);
        if (id != null) {
          if (type == TrackerType.anilist) {
            final fetched = await ref.read(anilistServiceProvider).getAnimeEntry(id);
            if (fetched != null) updatedEntries[type] = fetched;
          } else if (type == TrackerType.mal) {
            final fetched = await ref.read(malServiceProvider).getAnimeEntry(id);
            if (fetched != null) updatedEntries[type] = fetched;
          }
        }
      }

      if (status != null) {
        final repo = ref.read(watchProgressRepositoryProvider);
        final local = repo.getProgress(mediaId);
        if (local != null) {
          await repo.saveProgress(local.copyWith(status: status.toLowerCase()));
        }
      }

      state = currentState.copyWith(isLoading: false, entries: updatedEntries);
    } catch (e) {
      state = currentState.copyWith(isLoading: false);
      throw Exception('Failed to sync ${type.name}: $e');
    }
  }

  Future<void> trackAsCurrent(TrackerType type) async {
    final currentState = state;
    state = currentState.copyWith(isLoading: true);
    try {
      var binding = currentState.bindings.firstWhereOrNull((b) => b.type == type);
      final targetRemoteId = binding?.remoteId ?? mediaId;
      final id = int.tryParse(targetRemoteId);
      if (id != null) {
        if (binding == null) {
          await _repo.addBinding(mediaId, type, targetRemoteId);
        }
        UniversalMediaListEntry? newEntry;
        if (type == TrackerType.anilist) {
          newEntry = await ref.read(anilistServiceProvider).updateUserAnimeList(
            mediaId: id,
            status: 'CURRENT',
          );
        } else if (type == TrackerType.mal) {
          newEntry = await ref.read(malServiceProvider).updateUserAnimeList(
            mediaId: id,
            status: 'CURRENT',
          );
        }
        final updatedBindings = List<TrackerBinding>.from(currentState.bindings);
        if (binding == null) {
          updatedBindings.add(TrackerBinding(type: type, remoteId: targetRemoteId));
        }
        final updatedEntries = Map<TrackerType, UniversalMediaListEntry>.from(state.entries);
        if (newEntry != null) {
          updatedEntries[type] = newEntry;
        }
        state = state.copyWith(
          isLoading: false,
          bindings: updatedBindings,
          entries: updatedEntries,
        );
        return;
      }
      state = state.copyWith(isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false);
      AppLogger.e('Failed to track as current', e);
    }
  }

  LocalMediaRepositoryInterface get _repo => ref.read(localMediaRepoProvider);

  Future<void> _syncProgressFromActiveTracker(
    Map<TrackerType, UniversalMediaListEntry> entries,
  ) async {
    try {
      final authState = ref.read(authProvider);
      final activeType = authState.activePlatform == AuthPlatform.anilist
          ? TrackerType.anilist
          : TrackerType.mal;

      final entry = entries[activeType] ??
          entries[TrackerType.anilist] ??
          entries[TrackerType.mal];
      if (entry == null) return;

      final media = entry.media;
      final parsedNotes = CloudWatchProgressSync.parseNotes(entry.notes);
      final isCompleted = entry.status.toUpperCase() == 'COMPLETED';
      final int targetProgress;
      final int? savedSeconds = parsedNotes?.seconds;
      final int savedDuration = parsedNotes?.duration ?? 1440;

      if (parsedNotes != null) {
        targetProgress = parsedNotes.episode;
      } else if (isCompleted && (media.episodes != null && media.episodes! > 0)) {
        targetProgress = media.episodes!;
      } else {
        targetProgress = entry.progress;
      }

      if (targetProgress <= 0) return;

      final repo = ref.read(watchProgressRepositoryProvider);
      final local = repo.getProgress(mediaId);

      final episodesMap =
          Map<int, EpisodeProgress>.from(local?.episodesProgress ?? {});

      if (savedSeconds != null && savedSeconds > 0) {
        // Episodes before targetProgress were finished
        for (int i = 1; i < targetProgress; i++) {
          final existing = episodesMap[i];
          if (existing == null || !existing.isCompleted) {
            episodesMap[i] = EpisodeProgress(
              episodeNumber: i,
              episodeTitle: existing?.episodeTitle ?? 'Episode $i',
              episodeThumbnail: existing?.episodeThumbnail,
              progressInSeconds: existing?.progressInSeconds ??
                  (existing?.durationInSeconds ?? 1440),
              durationInSeconds: existing?.durationInSeconds ?? 1440,
              isCompleted: true,
              watchedAt: existing?.watchedAt ??
                  DateTime.fromMillisecondsSinceEpoch(0),
            );
          }
        }
        // Current episode is actively being watched at savedSeconds
        final existing = episodesMap[targetProgress];
        episodesMap[targetProgress] = EpisodeProgress(
          episodeNumber: targetProgress,
          episodeTitle: existing?.episodeTitle ?? 'Episode $targetProgress',
          episodeThumbnail: existing?.episodeThumbnail,
          progressInSeconds: savedSeconds,
          durationInSeconds: savedDuration,
          isCompleted: false,
          watchedAt: DateTime.now(),
        );
      } else {
        // Mark all episodes up to targetProgress as watched
        for (int i = 1; i <= targetProgress; i++) {
          final existing = episodesMap[i];
          if (existing == null || !existing.isCompleted) {
            episodesMap[i] = EpisodeProgress(
              episodeNumber: i,
              episodeTitle: existing?.episodeTitle ?? 'Episode $i',
              episodeThumbnail: existing?.episodeThumbnail,
              progressInSeconds: existing?.progressInSeconds ??
                  (existing?.durationInSeconds ?? 1440),
              durationInSeconds: existing?.durationInSeconds ?? 1440,
              isCompleted: true,
              watchedAt: existing?.watchedAt ??
                  DateTime.fromMillisecondsSinceEpoch(0),
            );
          }
        }
      }

      final statusLower = entry.status.toLowerCase();
      final totalEps = media.episodes ?? 0;
      final nextUpEpisode = (totalEps > 0 && targetProgress >= totalEps)
          ? totalEps
          : (targetProgress + 1);
      final isRemoteAhead =
          local == null || targetProgress >= local.currentEpisode;
      final resolvedCurrentEpisode = (savedSeconds != null && savedSeconds > 0)
          ? targetProgress
          : (isRemoteAhead ? nextUpEpisode : local.currentEpisode);
      final effectiveLastPlayedAt =
          isRemoteAhead ? DateTime.now() : (local.lastPlayedAt ?? DateTime.now());

      final updated = (local ??
              AnimeWatchProgressEntry(
                animeId: mediaId,
                animeTitle: media.title.english ??
                    media.title.romaji ??
                    media.title.native ??
                    '',
                animeFormat: media.format,
                animeCover:
                    media.coverImage.large ?? media.coverImage.medium ?? '',
                totalEpisodes: totalEps,
                episodesProgress: episodesMap,
                lastUpdated: DateTime.now(),
                lastPlayedAt: effectiveLastPlayedAt,
                currentEpisode: resolvedCurrentEpisode,
                status: isCompleted ? 'completed' : statusLower,
              ))
          .copyWith(
            episodesProgress: episodesMap,
            currentEpisode: resolvedCurrentEpisode,
            lastPlayedAt: effectiveLastPlayedAt,
            lastUpdated: DateTime.now(),
            status: isCompleted ? 'completed' : statusLower,
          );

      await repo.saveProgress(updated);
      AppLogger.d(
        'Synced local progress from ${activeType.name}: $targetProgress episodes marked as watched',
      );
    } catch (e) {
      AppLogger.e('Failed to sync local progress from tracker', e);
    }
  }

  Future<bool> toggleFavorite(UniversalMedia media) =>
      _repo.toggleFavorite(media);

  Future<bool> isFavorite(String mediaId) => _repo.isFavorite(mediaId);

  Future<UniversalMediaListEntry?> getLocalEntry() => _repo.getEntry(mediaId);

  Future<void> saveLocalEntry(
    UniversalMedia media, {
    required String status,
    required double score,
    required int progress,
    required int repeat,
    required String notes,
    required bool isPrivate,
    DateTime? startedAt,
    DateTime? completedAt,
  }) => _repo.saveEntry(
    media,
    status: status,
    score: score,
    progress: progress,
    repeat: repeat,
    notes: notes,
    isPrivate: isPrivate,
    startedAt: startedAt,
    completedAt: completedAt,
  );

  Future<void> deleteLocalEntry() => _repo.deleteEntry(mediaId);
}
