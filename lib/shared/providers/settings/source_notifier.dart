import 'dart:async';

import 'package:dartotsu_extension_bridge/dartotsu_extension_bridge.dart';
import 'package:get/instance_manager.dart';
import 'package:get/utils.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:ani_dash/core/models/anime/server_model.dart';
import 'package:ani_dash/core/repositories/source_repository.dart';
import 'package:ani_dash/core/utils/app_logger.dart';
import 'package:ani_dash/core/models/settings/source_model.dart';
import 'package:ani_dash/main.dart';

part 'source_notifier.g.dart';

@Riverpod(keepAlive: true)
class SourceNotifier extends _$SourceNotifier {
  final SourceRepository _repo = SourceRepository();

  @override
  SourceState build() {
    ref.onDispose(() {
      _managerSubscription?.cancel();
      for (final sub in _extensionSubscriptions) {
        sub.cancel();
      }
    });
    return const SourceState(isLoading: true);
  }

  StreamSubscription? _managerSubscription;
  final List<StreamSubscription> _extensionSubscriptions = [];

  Future<void> initialize() async {
    try {
      final extensionManager = Get.find<ExtensionManager>();
      // Listen for manager changes (e.g., swapping between Aniyomi/Mangayomi)
      _managerSubscription?.cancel();
      _managerSubscription = extensionManager.currentManagerRx.listen(
        _onManagerChanged,
      );

      // Perform initial setup with the current manager
      await _onManagerChanged(extensionManager.currentManager);
    } catch (e, st) {
      AppLogger.e('Error initializing extensions: $e\n$st');
      state = state.copyWith(isLoading: false);
    }
  }

  Future<void> _onManagerChanged(Extension manager) async {
    // Clear old extension subscriptions
    for (final sub in _extensionSubscriptions) {
      sub.cancel();
    }
    _extensionSubscriptions.clear();

    // Subscribe to installed extension changes from current manager
    _extensionSubscriptions.addAll([
      manager.installedAnimeExtensions.listen(
        (extensions) => _updateExtensions(ItemType.anime, extensions),
      ),
      manager.installedMangaExtensions.listen(
        (extensions) => _updateExtensions(ItemType.manga, extensions),
      ),
      manager.installedNovelExtensions.listen(
        (extensions) => _updateExtensions(ItemType.novel, extensions),
      ),
    ]);

    // Fetch initial data
    fetchSources(ItemType.anime);
    fetchSources(ItemType.manga);

    for (final type in [ItemType.anime, ItemType.manga]) {
      final Set<String> seen = {};
      final List<Source> extensions = [];

      Future<void> addExtensions(Extension m) async {
        try {
          List<Source> list = [];
          switch (type) {
            case ItemType.anime:
              list = await m.getInstalledAnimeExtensions();
              break;
            case ItemType.manga:
              list = await m.getInstalledMangaExtensions();
              break;
            case ItemType.novel:
              list = await m.getInstalledNovelExtensions();
              break;
          }
          for (final s in list) {
            final key = s.id ?? s.name ?? '';
            if (key.isNotEmpty && seen.add(key)) {
              extensions.add(s);
            }
          }
        } catch (_) {}
      }

      await addExtensions(manager);

      _updateExtensions(type, extensions);
    }

    state = state.copyWith(
      activeAnimeRepo: _repo.getActiveAnimeRepo(),
      activeMangaRepo: _repo.getActiveMangaRepo(),
      activeNovelRepo: _repo.getActiveNovelRepo(),
      isLoading: false,
    );

    _restoreActiveSources();
  }

  bool _isAdultSource(Source s) {
    final name = (s.name ?? '').toLowerCase();
    final id = (s.id ?? '').toLowerCase();
    return s.isNsfw == true ||
        name.contains('hanime') ||
        name.contains('hentai') ||
        name.contains('18+') ||
        name.contains('adult') ||
        id.contains('hanime') ||
        id.contains('hentai');
  }

  void _updateExtensions(ItemType type, List<Source> extensions) {
    switch (type) {
      case ItemType.anime:
        final merged = <String, Source>{};
        for (final s in extensions) {
          final key = s.id ?? s.name ?? '';
          if (key.isNotEmpty) merged[key] = s;
        }
        final normal = merged.values.where((s) => !_isAdultSource(s)).toList();
        final adult = merged.values.where((s) => _isAdultSource(s)).toList();
        state = state.copyWith(
          installedAnimeExtensions: normal,
          installedAdultAnimeExtensions: adult,
        );
        break;
      case ItemType.manga:
        final merged = <String, Source>{};
        for (final s in extensions) {
          final key = s.id ?? s.name ?? '';
          if (key.isNotEmpty) merged[key] = s;
        }
        final normal = merged.values.where((s) => !_isAdultSource(s)).toList();
        final adult = merged.values.where((s) => _isAdultSource(s)).toList();
        state = state.copyWith(
          installedMangaExtensions: normal,
          installedAdultMangaExtensions: adult,
        );
        break;
      case ItemType.novel:
        state = state.copyWith(installedNovelExtensions: extensions);
        break;
    }
    _restoreActiveSources();
  }

  void _restoreActiveSources() {
    final savedAnimeId = _repo.getActiveAnimeSourceId();
    // An explicit saved selection must not silently fall back to JustAnime
    // when switching extension engines or while a repository is still loading.
    final activeAnime =
        state.installedAnimeExtensions.firstWhereOrNull(
          (s) => s.id == savedAnimeId && !_isAdultSource(s),
        ) ??
        (savedAnimeId == null
            ? (state.installedAnimeExtensions.firstWhereOrNull(
                  (s) => (s.name ?? '').toLowerCase().contains('justanime'),
                ) ??
                state.installedAnimeExtensions.firstOrNull)
            : null);

    final activeAdult = state.installedAdultAnimeExtensions.firstOrNull;

    state = state.copyWith(
      activeAnimeSource: activeAnime,
      activeAdultAnimeSource: activeAdult,
      activeMangaSource:
          state.installedMangaExtensions.firstWhereOrNull(
            (s) => s.id == _repo.getActiveMangaSourceId() && !_isAdultSource(s),
          ) ??
          state.installedMangaExtensions.firstWhereOrNull(
            (s) => s.name?.toLowerCase().contains('mangadex') == true,
          ) ??
          state.installedMangaExtensions.firstOrNull,
      activeNovelSource:
          state.installedNovelExtensions.firstWhereOrNull(
            (s) => s.id == _repo.getActiveNovelSourceId(),
          ) ??
          state.installedNovelExtensions.firstOrNull,
    );
  }

  void setActiveSource(Source source) {
    if (_isAdultSource(source)) {
      if (source.itemType == ItemType.anime) {
        state = state.copyWith(activeAdultAnimeSource: source);
      }
      return;
    }
    switch (source.itemType) {
      case ItemType.anime:
        state = state.copyWith(
          activeAnimeSource: source,
          lastUpdatedSourceType: 'ANIME',
        );
        _repo.saveActiveAnimeSourceId(source.id!);
        break;
      case ItemType.manga:
        state = state.copyWith(
          activeMangaSource: source,
          lastUpdatedSourceType: 'MANGA',
        );
        _repo.saveActiveMangaSourceId(source.id!);
        break;
      case ItemType.novel:
        state = state.copyWith(
          activeNovelSource: source,
          lastUpdatedSourceType: 'NOVEL',
        );
        _repo.saveActiveNovelSourceId(source.id!);
        break;
      case null:
        break;
    }
  }

  void setActiveRepo(String repoUrl, ItemType mediaType) {
    switch (mediaType) {
      case ItemType.anime:
        state = state.copyWith(activeAnimeRepo: repoUrl);
        _repo.saveActiveAnimeRepo(repoUrl);
        break;
      case ItemType.manga:
        state = state.copyWith(activeMangaRepo: repoUrl);
        _repo.saveActiveMangaRepo(repoUrl);
        break;
      case ItemType.novel:
        state = state.copyWith(activeNovelRepo: repoUrl);
        _repo.saveActiveNovelRepo(repoUrl);
        break;
    }
  }

  Future<void> fetchSources(ItemType mediaType) async {
    final extensionManager = Get.find<ExtensionManager>();
    // Loading available repositories must not change the user's selected
    // AniYomi/MangaYomi engine as a side effect.
    final manager = extensionManager.currentManager;
    final isAniyomi =
        ExtensionType.fromManager(manager) == ExtensionType.aniyomi;
    if (mediaType == ItemType.anime) {
      final savedList = sharedPrefs.getStringList('saved_anime_repos') ?? [];
      final repos =
          <String>{
            if (!isAniyomi)
              'https://raw.githubusercontent.com/Mallyd11/mangayomi-anime-extensions/main/anime_index.json',
            if (!isAniyomi)
              'https://raw.githubusercontent.com/m2k3a/mangayomi-extensions/main/anime_index.json',
            ...savedList.where(
              (url) => isAniyomi
                  ? url.contains('index.min.json')
                  : !url.contains('index.min.json'),
            ),
          }.toList();
      await manager.fetchAvailableAnimeExtensions(repos);
    } else if (mediaType == ItemType.manga) {
      final repos =
          <String>{
            if (!isAniyomi)
              'https://raw.githubusercontent.com/kodjodevf/mangayomi-extensions/main/index.json',
            ...?sharedPrefs
                .getStringList('saved_manga_repos')
                ?.where((url) => isAniyomi
                    ? url.contains('index.min.json')
                    : !url.contains('index.min.json')),
          }.toList();
      await manager.fetchAvailableMangaExtensions(repos);
    } else {
      if (state.activeNovelRepo.isEmpty) return;
      await manager.fetchAvailableNovelExtensions([state.activeNovelRepo]);
    }
  }

  Future<Pages> search(
    String query, {
    int page = 1,
    List filters = const [],
  }) async {
    try {
      if (state.activeAnimeSource == null) {
        // Auto-select first installed extension if available
        final firstSource = state.installedAnimeExtensions.firstOrNull;
        if (firstSource != null) {
          AppLogger.d('Auto-selecting extension source: ${firstSource.name}');
          setActiveSource(firstSource);
        } else {
          AppLogger.w('Search: No installed anime extensions available');
          return Pages(list: []);
        }
      }
      AppLogger.d(
        'Search: Using source "${state.activeAnimeSource!.name}" (id: ${state.activeAnimeSource!.id}, itemType: ${state.activeAnimeSource!.itemType}) for query "$query"',
      );
      final result = await state.activeAnimeSource!.methods
          .search(query, page, filters)
          .timeout(const Duration(seconds: 10));
      AppLogger.d('Search: Got ${result.list.length} results');
      return result;
    } catch (err, st) {
      AppLogger.e(
        'Search failed for query "$query" with source "${state.activeAnimeSource?.name}" (id: ${state.activeAnimeSource?.id})',
        err,
        st,
      );
      return Pages(list: []);
    }
  }

  Future<DMedia?> getDetails(DMedia media) async {
    try {
      if (state.activeAnimeSource == null) {
        final firstSource = state.installedAnimeExtensions.firstOrNull;
        if (firstSource != null) {
          setActiveSource(firstSource);
        } else {
          return null;
        }
      }
      return await state.activeAnimeSource!.methods
          .getDetail(media)
          .timeout(const Duration(seconds: 25));
    } catch (err) {
      AppLogger.e(err);
      return null;
    }
  }

  Future<List<Video?>> getSources(DEpisode episode) async {
    try {
      if (state.activeAnimeSource == null) {
        final firstSource = state.installedAnimeExtensions.firstOrNull;
        if (firstSource != null) {
          setActiveSource(firstSource);
        } else {
          return [];
        }
      }
      return await state.activeAnimeSource!.methods
          .getVideoList(episode)
          .timeout(const Duration(seconds: 10));
    } catch (err) {
      AppLogger.e(err);
      return [];
    }
  }

  Future<List<ServerData?>> getServers(
    String animeId,
    String episodeId,
    String episodeNumber,
  ) async {
    return [];
    //   try {
    //     if (state.activeAnimeSource == null) return [];
    //     final anilist = ref.read(anilistServiceProvider);
    //     final service = _getService(anilist);
    //     return state.activeAnimeSource!.isForAniDash ?? false
    //         ? await service.getSupportedServers(animeId, episodeId, episodeNumber)
    //         : [] as List<ServerData?>;
    //   } catch (err) {
    //     AppLogger.e(err);
    //     return [];
    //   }
    // }
  }
}
